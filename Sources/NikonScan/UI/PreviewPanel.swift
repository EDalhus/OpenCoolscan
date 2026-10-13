import SwiftUI
import AppKit

// MARK: - Image Window (Processed / Natural tabs, rulers, crop marquee)

struct ImageWindow: View {
    let image: NSImage?
    let frameNumber: Int
    @ObservedObject var settings: ScanSettings
    @Binding var zoom: CGFloat?
    @Binding var hoverRGB: PixelRGB?

    @State private var pan: CGSize = .zero
    @State private var sampler: PixelSampler?
    @StateObject private var scrollMonitor = ScrollWheelMonitor()

    private let tabHeight: CGFloat = 19
    private let topRuler: CGFloat = 18
    private let leftRuler: CGFloat = 16
    private let scroller: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: -1) {
            HStack(spacing: -1) {
                AquaTab(title: "Processed", selected: !settings.showOriginal, fontSize: 12.5) {
                    settings.showOriginal = false
                }
                AquaTab(title: "Natural", selected: settings.showOriginal, fontSize: 12.5) {
                    settings.showOriginal = true
                }
            }
            .frame(height: tabHeight)
            .padding(.leading, 5)
            .zIndex(1)

            GeometryReader { geo in
                let content = CGSize(width: geo.size.width - leftRuler - scroller,
                                     height: geo.size.height - topRuler - scroller)
                let rect = imageRect(in: content)

                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Color.white.frame(width: leftRuler)
                        RulerView(axis: .horizontal, imageRect: rect, pixelLength: pixelLength(.horizontal))
                        Color.white.frame(width: scroller)
                    }
                    .frame(height: topRuler)
                    .overlay(alignment: .bottom) { Color(hex: 0x9A9A9A).frame(height: 1) }

                    HStack(spacing: 0) {
                        RulerView(axis: .vertical, imageRect: rect, pixelLength: pixelLength(.vertical))
                            .frame(width: leftRuler)
                            .overlay(alignment: .trailing) { Color(hex: 0x9A9A9A).frame(width: 1) }
                        imageArea(rect: rect)
                            .frame(width: content.width, height: content.height)
                            .clipped()
                        ScrollerTrack(axis: .vertical).frame(width: scroller)
                    }

                    HStack(spacing: 0) {
                        ScrollerTrack(axis: .horizontal)
                        GrowBox().frame(width: scroller)
                    }
                    .frame(height: scroller)
                }
                .onAppear { scrollMonitor.onScroll = { dx, dy in scrollBy(dx: dx, dy: dy, content: content, rect: rect) } }
                .onChange(of: rect) { newRect in
                    scrollMonitor.onScroll = { dx, dy in scrollBy(dx: dx, dy: dy, content: content, rect: newRect) }
                }
            }
            .background { Color.white }
            .overlay(Rectangle().stroke(Color(hex: 0x6A6A6A), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 3)
        }
        .onAppear { rebuildSampler() }
        .onChange(of: image) { _ in rebuildSampler() }
        .onChange(of: zoom) { z in if z == nil { pan = .zero } }
    }

    // MARK: Image area

    @ViewBuilder
    private func imageArea(rect: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            Color.aquaImageArea

            if let image {
                // Film-rebate strips above and below the frame
                Color(hex: 0xF1EFE7)
                    .frame(width: rect.width, height: rect.height + 9)
                    .offset(x: rect.minX, y: rect.minY - 4)

                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)

                if !settings.showOriginal {
                    CropOverlay(cropRect: $settings.cropRect)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
            } else {
                Text("Frame \(frameNumber) — press Preview")
                    .font(.lucida(12))
                    .foregroundColor(Color.white.opacity(0.75))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let p):
                scrollMonitor.isHovering = true
                guard rect.contains(p), let sampler else { hoverRGB = nil; return }
                hoverRGB = sampler.rgb(at: CGPoint(x: (p.x - rect.minX) / rect.width,
                                                   y: (p.y - rect.minY) / rect.height))
            case .ended:
                scrollMonitor.isHovering = false
                hoverRGB = nil
            }
        }
    }

    private func imageRect(in content: CGSize) -> CGRect {
        guard let px = pixelSize(of: image), px.width > 0, px.height > 0 else {
            return CGRect(x: 0, y: 0, width: content.width, height: content.height)
        }
        let padX: CGFloat = 6, padY: CGFloat = 8
        let avail = CGSize(width: max(10, content.width - padX * 2), height: max(10, content.height - padY * 2))
        let aspect = CGFloat(px.width) / CGFloat(px.height)
        var size = avail.width / avail.height > aspect
            ? CGSize(width: avail.height * aspect, height: avail.height)
            : CGSize(width: avail.width, height: avail.width / aspect)
        let z = zoom ?? 1
        size = CGSize(width: size.width * z, height: size.height * z)
        return CGRect(x: (content.width - size.width) / 2 + pan.width,
                      y: (content.height - size.height) / 2 + pan.height,
                      width: size.width, height: size.height)
    }

    private func pixelLength(_ axis: Axis) -> CGFloat {
        guard let px = pixelSize(of: image) else { return 0 }
        return CGFloat(axis == .horizontal ? px.width : px.height)
    }

    private func scrollBy(dx: CGFloat, dy: CGFloat, content: CGSize, rect: CGRect) {
        guard zoom != nil else { return }
        let maxX = max(0, (rect.width - content.width) / 2 + 20)
        let maxY = max(0, (rect.height - content.height) / 2 + 20)
        pan = CGSize(width: min(maxX, max(-maxX, pan.width + dx)),
                     height: min(maxY, max(-maxY, pan.height + dy)))
    }

    private func rebuildSampler() {
        sampler = image.flatMap { PixelSampler(image: $0) }
        hoverRGB = nil
    }
}

// MARK: - Rulers

struct RulerView: View {
    let axis: Axis
    let imageRect: CGRect
    let pixelLength: CGFloat

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            let imgStart = axis == .horizontal ? imageRect.minX : imageRect.minY
            let imgExtent = axis == .horizontal ? imageRect.width : imageRect.height
            guard pixelLength > 0, imgExtent > 0 else { return }

            let scale = imgExtent / pixelLength        // points per pixel
            let steps: [CGFloat] = [10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000]
            let major = steps.first { $0 * scale >= 34 } ?? 10000
            let minor = major / 10

            let length = axis == .horizontal ? size.width : size.height
            let thick = axis == .horizontal ? size.height : size.width
            let first = (floor(-imgStart / scale / minor) * minor)
            let last = (length - imgStart) / scale

            var v = first
            var ticks = Path()
            while v <= last {
                let pos = imgStart + v * scale
                let isMajor = abs(v.truncatingRemainder(dividingBy: major)) < 0.5
                let isHalf = abs(v.truncatingRemainder(dividingBy: major / 2)) < 0.5
                let tick: CGFloat = isMajor ? thick : (isHalf ? thick * 0.4 : thick * 0.22)
                if axis == .horizontal {
                    ticks.move(to: CGPoint(x: pos, y: thick))
                    ticks.addLine(to: CGPoint(x: pos, y: thick - tick))
                } else {
                    ticks.move(to: CGPoint(x: thick, y: pos))
                    ticks.addLine(to: CGPoint(x: thick - tick, y: pos))
                }
                if isMajor && v >= 0 {
                    let label = Text(verbatim: String(Int(v))).font(.lucida(9)).foregroundColor(.black)
                    if axis == .horizontal {
                        ctx.draw(label, at: CGPoint(x: pos + 2, y: 0), anchor: .topLeading)
                    } else {
                        var c = ctx
                        c.translateBy(x: 1, y: pos - 2)
                        c.rotate(by: .degrees(-90))
                        c.draw(label, at: .zero, anchor: .topLeading)
                    }
                }
                v += minor
            }
            ctx.stroke(ticks, with: .color(.black), lineWidth: 0.75)
        }
    }
}

struct ScrollerTrack: View {
    let axis: Axis
    var body: some View {
        LinearGradient(colors: [Color(hex: 0xE4E4E4), Color(hex: 0xFAFAFA), Color(hex: 0xEDEDED)],
                       startPoint: axis == .vertical ? .leading : .top,
                       endPoint: axis == .vertical ? .trailing : .bottom)
            .overlay(alignment: axis == .vertical ? .leading : .top) {
                Color(hex: 0xBDBDBD).frame(width: axis == .vertical ? 1 : nil,
                                           height: axis == .horizontal ? 1 : nil)
            }
    }
}

struct GrowBox: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0xF2F2F2)))
            var p = Path()
            var i: CGFloat = -size.height
            while i < size.width {
                p.move(to: CGPoint(x: i, y: size.height))
                p.addLine(to: CGPoint(x: i + size.height, y: 0))
                i += 3.5
            }
            ctx.stroke(p, with: .color(Color(hex: 0x8A8A8A)), lineWidth: 0.75)
        }
        .overlay(Rectangle().stroke(Color(hex: 0xBDBDBD), lineWidth: 1))
    }
}

// MARK: - Pixel sampling (RGB readout under the pointer)

final class PixelSampler {
    private let data: [UInt8]
    private let width: Int
    private let height: Int

    init?(image: NSImage, maxDimension: Int = 1024) {
        var rect = NSRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        let scale = min(1, CGFloat(maxDimension) / CGFloat(max(cg.width, cg.height)))
        let w = max(1, Int(CGFloat(cg.width) * scale)), h = max(1, Int(CGFloat(cg.height) * scale))
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = buffer.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        data = buffer; width = w; height = h
    }

    /// `p` is normalized with a top-left origin.
    func rgb(at p: CGPoint) -> PixelRGB? {
        let x = Int(p.x * CGFloat(width)), y = Int(p.y * CGFloat(height))
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let i = (y * width + x) * 4
        return PixelRGB(r: Int(data[i]), g: Int(data[i + 1]), b: Int(data[i + 2]))
    }
}

// MARK: - Scroll-wheel panning while zoomed

final class ScrollWheelMonitor: ObservableObject {
    var isHovering = false
    var onScroll: ((CGFloat, CGFloat) -> Void)?
    private var token: Any?

    init() {
        token = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.isHovering, let onScroll = self.onScroll else { return event }
            onScroll(event.scrollingDeltaX, event.scrollingDeltaY)
            return event
        }
    }

    deinit {
        if let token { NSEvent.removeMonitor(token) }
    }
}

// MARK: - Crop Overlay (dashed marquee, Nikon Scan style)

struct CropOverlay: View {
    @Binding var cropRect: CGRect
    @State private var dragStartCrop: CGRect?
    @State private var drawing = false
    @State private var handleStartCrop: CGRect?

    private var isFullFrame: Bool {
        cropRect.minX < 0.001 && cropRect.minY < 0.001 && cropRect.width > 0.999 && cropRect.height > 0.999
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let r = CGRect(x: cropRect.minX * w, y: cropRect.minY * h,
                           width: cropRect.width * w, height: cropRect.height * h)
            let marquee = r.insetBy(dx: 0.5, dy: 0.5)

            ZStack(alignment: .topLeading) {
                Color.clear

                Rectangle()
                    .stroke(Color.black.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .frame(width: marquee.width, height: marquee.height)
                    .offset(x: marquee.minX, y: marquee.minY)
                Rectangle()
                    .stroke(Color(hex: 0xF0E2A8), style: StrokeStyle(lineWidth: 1, dash: [4, 3], dashPhase: 3.5))
                    .frame(width: marquee.width, height: marquee.height)
                    .offset(x: marquee.minX, y: marquee.minY)

                if !isFullFrame {
                    ForEach(cropHandles(r), id: \.id) { handle in
                        Color.clear
                            .frame(width: 14, height: 14)
                            .contentShape(Rectangle())
                            .offset(x: handle.point.x - 7, y: handle.point.y - 7)
                            .gesture(
                                DragGesture(minimumDistance: 1)
                                    .onChanged { drag in
                                        if handleStartCrop == nil { handleStartCrop = cropRect }
                                        updateCrop(handle: handle, translation: drag.translation,
                                                   size: geo.size, start: handleStartCrop ?? cropRect)
                                    }
                                    .onEnded { _ in handleStartCrop = nil }
                            )
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { drag in
                        if dragStartCrop == nil {
                            dragStartCrop = cropRect
                            // Drag outside the current crop (or on a full frame) draws a new marquee.
                            drawing = isFullFrame || !r.contains(drag.startLocation)
                        }
                        let start = dragStartCrop ?? cropRect
                        if drawing {
                            let a = CGPoint(x: clamp(drag.startLocation.x / w), y: clamp(drag.startLocation.y / h))
                            let b = CGPoint(x: clamp(drag.location.x / w), y: clamp(drag.location.y / h))
                            cropRect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                                              width: max(0.02, abs(b.x - a.x)), height: max(0.02, abs(b.y - a.y)))
                        } else {
                            let dx = drag.translation.width / w
                            let dy = drag.translation.height / h
                            cropRect.origin.x = min(max(0, start.origin.x + dx), 1 - start.width)
                            cropRect.origin.y = min(max(0, start.origin.y + dy), 1 - start.height)
                            cropRect.size = start.size
                        }
                    }
                    .onEnded { _ in
                        dragStartCrop = nil
                        if cropRect.width < 0.05 || cropRect.height < 0.05 {
                            cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                        }
                    }
            )
            .onTapGesture(count: 2) { cropRect = CGRect(x: 0, y: 0, width: 1, height: 1) }
        }
    }

    private func clamp(_ v: CGFloat) -> CGFloat { min(1, max(0, v)) }

    struct CropHandle: Identifiable {
        let id: String
        let point: CGPoint
    }

    private func cropHandles(_ r: CGRect) -> [CropHandle] {
        [
            CropHandle(id: "tl", point: r.origin),
            CropHandle(id: "tr", point: CGPoint(x: r.maxX, y: r.minY)),
            CropHandle(id: "bl", point: CGPoint(x: r.minX, y: r.maxY)),
            CropHandle(id: "br", point: CGPoint(x: r.maxX, y: r.maxY)),
        ]
    }

    private func updateCrop(handle: CropHandle, translation: CGSize, size: CGSize, start: CGRect) {
        let dx = translation.width  / size.width
        let dy = translation.height / size.height
        var rect = start
        let minSize: CGFloat = 0.05

        switch handle.id {
        case "tl":
            let newX = min(start.maxX - minSize, max(0, start.minX + dx))
            let newY = min(start.maxY - minSize, max(0, start.minY + dy))
            rect = CGRect(x: newX, y: newY, width: start.maxX - newX, height: start.maxY - newY)
        case "tr":
            let newY = min(start.maxY - minSize, max(0, start.minY + dy))
            rect.size.width = max(minSize, min(1 - start.minX, start.width + dx))
            rect.size.height = start.maxY - newY
            rect.origin.y = newY
        case "bl":
            let newX = min(start.maxX - minSize, max(0, start.minX + dx))
            rect.size.width = start.maxX - newX
            rect.size.height = max(minSize, min(1 - start.minY, start.height + dy))
            rect.origin.x = newX
        case "br":
            rect.size.width = max(minSize, min(1 - start.minX, start.width + dx))
            rect.size.height = max(minSize, min(1 - start.minY, start.height + dy))
        default: break
        }
        cropRect = rect
    }
}
