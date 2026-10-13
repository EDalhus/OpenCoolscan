import Foundation
import CoreImage
import AppKit

struct ImageProcessor {
    private static let sharedContext = CIContext(options: [.useSoftwareRenderer: false])

    /// `includeCrop: false` renders the full frame so the UI can draw the crop marquee on top.
    static func apply(settings: ScanSettings, to image: NSImage, includeCrop: Bool = true) -> NSImage {
        var rect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return image }
        let ciImage = CIImage(cgImage: cgImage)

        var processed = ciImage

        // 0. User crop (normalized 0…1) — applied in image space before tone work
        if includeCrop {
            processed = applyCrop(settings.cropRect, to: processed)
        }

        // 1. Exposure
        if settings.brightness != 0 {
            if let filter = CIFilter(name: "CIExposureAdjust") {
                filter.setValue(processed, forKey: kCIInputImageKey)
                filter.setValue(Float(settings.brightness), forKey: "inputEV")
                processed = filter.outputImage ?? processed
            }
        }

        // 2. Contrast
        if settings.contrast != 0 {
            let contrastValue = Float(1.0 + settings.contrast * 0.25)
            if let filter = CIFilter(name: "CIColorControls") {
                filter.setValue(processed, forKey: kCIInputImageKey)
                filter.setValue(Float(0),        forKey: kCIInputBrightnessKey)
                filter.setValue(contrastValue,   forKey: kCIInputContrastKey)
                filter.setValue(Float(1.0),      forKey: kCIInputSaturationKey)
                processed = filter.outputImage ?? processed
            }
        }

        // 3. Saturation / grayscale
        let forceGray = settings.isGrayscale
        if settings.saturation != 0 || forceGray {
            let satValue = forceGray ? Float(0) : Float(1.0 + settings.saturation / 100.0)
            if let filter = CIFilter(name: "CIColorControls") {
                filter.setValue(processed, forKey: kCIInputImageKey)
                filter.setValue(Float(0),    forKey: kCIInputBrightnessKey)
                filter.setValue(Float(1.0),  forKey: kCIInputContrastKey)
                filter.setValue(satValue,    forKey: kCIInputSaturationKey)
                processed = filter.outputImage ?? processed
            }
        }

        // 4. Gamma
        if abs(settings.gamma - 1.0) > 0.01 {
            if let filter = CIFilter(name: "CIGammaAdjust") {
                filter.setValue(processed, forKey: kCIInputImageKey)
                filter.setValue(Float(1.0 / settings.gamma), forKey: "inputPower")
                processed = filter.outputImage ?? processed
            }
        }

        // 5. Color balance
        let cb = settings.colorBalance
        if cb.x != 0 || cb.y != 0 || cb.z != 0 {
            if let filter = CIFilter(name: "CIColorMatrix") {
                filter.setValue(processed, forKey: kCIInputImageKey)
                filter.setValue(CIVector(x: 1 + cb.x * 0.01, y: 0, z: 0, w: 0), forKey: "inputRVector")
                filter.setValue(CIVector(x: 0, y: 1 + cb.y * 0.01, z: 0, w: 0), forKey: "inputGVector")
                filter.setValue(CIVector(x: 0, y: 0, z: 1 + cb.z * 0.01, w: 0), forKey: "inputBVector")
                filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
                filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")
                processed = filter.outputImage ?? processed
            }
        }

        // 6. Tone curves
        processed = applyCurves(settings.curves, to: processed)

        // 7. Rotation
        if settings.rotation != 0 {
            let radians = CGFloat(settings.rotation) * .pi / 180.0
            processed = processed.transformed(by: CGAffineTransform(rotationAngle: radians))
            processed = processed.transformed(by: CGAffineTransform(
                translationX: -processed.extent.minX,
                y: -processed.extent.minY
            ))
        }

        // 8. Frame alignment trim (on original pixel space estimate)
        let rightTrim = computeFrameTrim(cgImage: cgImage, settings: settings)
        if rightTrim > 0 {
            let ext = processed.extent
            // Scale trim if crop already reduced width
            let scaleX = ext.width / CGFloat(cgImage.width)
            let trimScaled = CGFloat(rightTrim) * scaleX
            let newWidth = ext.width - trimScaled
            if newWidth > 32 {
                let cropRect = CGRect(x: ext.minX, y: ext.minY, width: newWidth, height: ext.height)
                processed = processed.cropped(to: cropRect)
                processed = processed.transformed(by: CGAffineTransform(
                    translationX: -processed.extent.minX, y: -processed.extent.minY
                ))
            }
        }

        guard let cgOut = sharedContext.createCGImage(processed, from: processed.extent) else { return image }
        let outSize = CGSize(width: processed.extent.width, height: processed.extent.height)
        return NSImage(cgImage: cgOut, size: outSize)
    }

    // MARK: - Crop

    private static func applyCrop(_ crop: CGRect, to image: CIImage) -> CIImage {
        let ext = image.extent
        guard ext.width > 1, ext.height > 1 else { return image }

        let clamped = CGRect(
            x: max(0, min(1, crop.origin.x)),
            y: max(0, min(1, crop.origin.y)),
            width: max(0.05, min(1, crop.width)),
            height: max(0.05, min(1, crop.height))
        )
        if abs(clamped.minX) < 0.001, abs(clamped.minY) < 0.001,
           abs(clamped.width - 1) < 0.001, abs(clamped.height - 1) < 0.001 {
            return image
        }

        // CIImage y-origin is bottom-left; UI crop is top-left normalized.
        let x = ext.minX + clamped.minX * ext.width
        let w = clamped.width * ext.width
        let h = clamped.height * ext.height
        let y = ext.minY + (1.0 - clamped.minY - clamped.height) * ext.height

        var cropped = image.cropped(to: CGRect(x: x, y: y, width: w, height: h))
        cropped = cropped.transformed(by: CGAffineTransform(
            translationX: -cropped.extent.minX, y: -cropped.extent.minY
        ))
        return cropped
    }

    // MARK: - Frame alignment

    private static func computeFrameTrim(cgImage: CGImage, settings: ScanSettings) -> Int {
        var autoCrop = 0
        if settings.autoAlign {
            if let edgeX = detectFrameRightEdge(in: cgImage) {
                autoCrop = cgImage.width - edgeX
            }
        }
        let total = autoCrop + settings.alignmentOffset
        return max(0, min(total, Int(Double(cgImage.width) * 0.40)))
    }

    private static func detectFrameRightEdge(in cgImage: CGImage,
                                              searchFraction: Double = 0.30) -> Int? {
        let origWidth  = cgImage.width
        let origHeight = cgImage.height
        guard origWidth > 128, origHeight > 128 else { return nil }

        let thumbW = 200
        let thumbH = 100
        var pixels = [UInt8](repeating: 0, count: thumbW * thumbH * 4)
        guard let ctx = CGContext(
            data: &pixels,
            width: thumbW, height: thumbH,
            bitsPerComponent: 8,
            bytesPerRow: thumbW * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: thumbW, height: thumbH))

        let searchStart = Int(Double(thumbW) * (1.0 - searchFraction))

        for x in stride(from: thumbW - 2, through: searchStart, by: -1) {
            var sum: Double = 0
            var sumSq: Double = 0
            for y in 0..<thumbH {
                let idx = (y * thumbW + x) * 4
                let lum = Double(pixels[idx])     * 0.299
                        + Double(pixels[idx + 1]) * 0.587
                        + Double(pixels[idx + 2]) * 0.114
                sum   += lum
                sumSq += lum * lum
            }
            let mean     = sum / Double(thumbH)
            let variance = sumSq / Double(thumbH) - mean * mean
            let stddev   = sqrt(max(0, variance))

            if stddev < 10.0 && (mean < 30.0 || mean > 225.0) {
                let origX = Int(Double(x) / Double(thumbW) * Double(origWidth))
                guard origX > origWidth / 3 else { return nil }
                return origX
            }
        }
        return nil
    }

    private static func applyCurves(_ curves: Curves, to image: CIImage) -> CIImage {
        let isLinear = curves.composite == .linear &&
                       curves.red == .linear &&
                       curves.green == .linear &&
                       curves.blue == .linear
        if isLinear { return image }

        let lutSize = 16
        let count = lutSize * lutSize * lutSize * 4
        var cubeData = [Float](repeating: 0, count: count)

        for b in 0..<lutSize {
            for g in 0..<lutSize {
                for r in 0..<lutSize {
                    let rf = Double(r) / Double(lutSize - 1)
                    let gf = Double(g) / Double(lutSize - 1)
                    let bf = Double(b) / Double(lutSize - 1)

                    let rc = curves.composite.output(for: rf)
                    let gc = curves.composite.output(for: gf)
                    let bc = curves.composite.output(for: bf)

                    let idx = (b * lutSize * lutSize + g * lutSize + r) * 4
                    cubeData[idx + 0] = Float(curves.red.output(for: rc))
                    cubeData[idx + 1] = Float(curves.green.output(for: gc))
                    cubeData[idx + 2] = Float(curves.blue.output(for: bc))
                    cubeData[idx + 3] = 1.0
                }
            }
        }

        let cubeDataRef = Data(bytes: cubeData, count: cubeData.count * MemoryLayout<Float>.size)
        guard let filter = CIFilter(name: "CIColorCube") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(lutSize, forKey: "inputCubeDimension")
        filter.setValue(cubeDataRef as NSData, forKey: "inputCubeData")
        return filter.outputImage ?? image
    }
}
