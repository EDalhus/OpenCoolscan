import Foundation
import AppKit
import CoreGraphics

// Simulated scanner for use without physical hardware
struct SimulatedScanner {

    static func preview(settings: ScanSettings, frame: Int = 0, progress: @escaping @Sendable (Double) -> Void) async throws -> NSImage {
        try await Task.detached {
            for i in 1...5 {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 100_000_000)
                await MainActor.run { progress(Double(i) / 5.0) }
            }
            return generateSampleImage(settings: settings, frame: frame, size: CGSize(width: 800, height: 533))
        }.value
    }

    static func scan(settings: ScanSettings, frame: Int = 0, progress: @escaping @Sendable (Double) -> Void) async throws -> NSImage {
        try await Task.detached {
            let steps = 20
            for i in 1...steps {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 150_000_000)
                await MainActor.run { progress(Double(i) / Double(steps)) }
            }
            let pixelsPerMM = Double(settings.resolution) / 25.4
            let width  = max(64, Int(36.0 * pixelsPerMM * Double(settings.cropRect.width)))
            let height = max(64, Int(24.0 * pixelsPerMM * Double(settings.cropRect.height)))
            return generateSampleImage(settings: settings, frame: frame, size: CGSize(width: width, height: height))
        }.value
    }

    private static func generateSampleImage(settings: ScanSettings, frame: Int, size: CGSize) -> NSImage {
        let width = max(1, Int(size.width.rounded()))
        let height = max(1, Int(size.height.rounded()))

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return NSImage(size: size)
        }

        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = ctx
            drawFilmFrame(ctx: ctx.cgContext, size: CGSize(width: width, height: height), settings: settings, frame: frame)
        }
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        return image
    }

    private static func drawFilmFrame(ctx: CGContext, size: CGSize, settings: ScanSettings, frame: Int) {
        let bounds = CGRect(origin: .zero, size: size)
        drawSimulatedScene(ctx: ctx, bounds: bounds, settings: settings, frame: frame)
        addFilmGrain(ctx: ctx, bounds: bounds)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: "Lucida Grande", size: max(10, size.height * 0.035))
                ?? NSFont.systemFont(ofSize: max(10, size.height * 0.035)),
            .foregroundColor: NSColor.white.withAlphaComponent(0.6)
        ]
        let str = NSAttributedString(string: "Frame \(frame + 1)", attributes: attrs)
        let strSize = str.size()
        str.draw(at: CGPoint(
            x: (size.width - strSize.width) / 2,
            y: size.height * 0.54 - strSize.height * 1.4
        ))
    }

    /// Sky-over-horizon gradient (matches the design reference thumbnails).
    private static func drawSimulatedScene(ctx: CGContext, bounds: CGRect, settings: ScanSettings, frame: Int) {
        let w = bounds.width, h = bounds.height
        let isColor = settings.filmType.isColor

        func color(_ hex: UInt32) -> CGColor {
            let r = CGFloat((hex >> 16) & 0xFF) / 255
            let g = CGFloat((hex >> 8) & 0xFF) / 255
            let b = CGFloat(hex & 0xFF) / 255
            if !isColor {
                let lum = 0.299 * r + 0.587 * g + 0.114 * b
                return CGColor(red: lum, green: lum, blue: lum, alpha: 1)
            }
            return CGColor(red: r, green: g, blue: b, alpha: 1)
        }

        // Stops listed top → bottom (location 0 = top of frame).
        var stops: [(CGFloat, UInt32)] = [
            (0.00, 0x556C9C), (0.30, 0x6A82B4), (0.43, 0x7D95C6),
            (0.46, 0xE6EBF3), (0.55, 0xCED6E5), (0.70, 0xA9B3C8),
            (0.85, 0x6E7B98), (1.00, 0x354260)
        ]
        switch frame % 6 {
        case 1: stops[0].1 = 0x3F5588; stops[1].1 = 0x5870A6
        case 3: stops = [(0.00, 0x7D93C4), (0.40, 0xB4C2E0), (0.52, 0xF2F4F8), (0.62, 0xC7D0E2), (1.00, 0x6E7FA6)]
        case 4: stops[5].1 = 0x9A9078; stops[6].1 = 0x6B5A45; stops[7].1 = 0x2E2A2C
        case 5: stops[0].1 = 0x6077A8; stops[3].1 = 0xF4F6FA
        default: break
        }

        let colors = stops.map { color($0.1) } as CFArray
        // CoreGraphics' origin is bottom-left, so flip locations.
        let locations = stops.map { 1 - $0.0 }
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors, locations: locations) else { return }

        ctx.saveGState()
        if frame % 6 == 3 {
            // Slightly tilted horizon
            ctx.translateBy(x: w / 2, y: h / 2)
            ctx.rotate(by: 0.06)
            ctx.translateBy(x: -w / 2, y: -h / 2)
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: -h * 0.1), end: CGPoint(x: 0, y: h * 1.1),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        } else {
            ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: h),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        ctx.restoreGState()

        if frame % 6 == 2 {
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
            ctx.fill(CGRect(x: 0, y: h * 0.54, width: w, height: max(1, h * 0.003)))
        }
    }

    private static func addFilmGrain(ctx: CGContext, bounds: CGRect) {
        let grainSize: Int = 3
        let w = Int(bounds.width), h = Int(bounds.height)
        guard w > grainSize, h > grainSize else { return }
        guard let overlay = CGContext(
            data: nil,
            width: w / grainSize,
            height: h / grainSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        for y in 0..<(h / grainSize) {
            for x in 0..<(w / grainSize) {
                let noise = CGFloat.random(in: -0.05...0.05)
                overlay.setFillColor(CGColor(red: noise+0.5, green: noise+0.5, blue: noise+0.5, alpha: 0.07))
                overlay.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }

        if let grainImage = overlay.makeImage() {
            ctx.draw(grainImage, in: bounds)
        }
    }
}
