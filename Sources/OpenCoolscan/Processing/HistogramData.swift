import Foundation
import AppKit
import CoreGraphics

struct HistogramData {
    var red:       [Int]
    var green:     [Int]
    var blue:      [Int]
    var luminance: [Int]

    static var empty: HistogramData {
        HistogramData(
            red:       [Int](repeating: 0, count: 256),
            green:     [Int](repeating: 0, count: 256),
            blue:      [Int](repeating: 0, count: 256),
            luminance: [Int](repeating: 0, count: 256)
        )
    }

    static func compute(from image: NSImage) -> HistogramData {
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let cgImage = bitmapRep.cgImage else {
            return .empty
        }

        let w = cgImage.width, h = cgImage.height
        guard let data = cgImage.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return .empty }

        var r = [Int](repeating: 0, count: 256)
        var g = [Int](repeating: 0, count: 256)
        var b = [Int](repeating: 0, count: 256)
        var l = [Int](repeating: 0, count: 256)

        let bytesPerRow = cgImage.bytesPerRow
        let bpp = max(1, cgImage.bitsPerPixel / 8)
        let byteCount = CFDataGetLength(data)

        let stepX = max(1, w / 200)
        let stepY = max(1, h / 133)

        var y = 0
        while y < h {
            var x = 0
            while x < w {
                let offset = y * bytesPerRow + x * bpp
                guard offset + max(0, bpp - 1) < byteCount else {
                    x += stepX
                    continue
                }

                let rv: Int
                let gv: Int
                let bv: Int
                if bpp >= 3 {
                    rv = Int(ptr[offset])
                    gv = Int(ptr[offset + 1])
                    bv = Int(ptr[offset + 2])
                } else {
                    // Grayscale / single-channel
                    let v = Int(ptr[offset])
                    rv = v; gv = v; bv = v
                }

                r[min(255, rv)] += 1
                g[min(255, gv)] += 1
                b[min(255, bv)] += 1
                let lv = Int(0.299 * Double(rv) + 0.587 * Double(gv) + 0.114 * Double(bv))
                l[min(255, max(0, lv))] += 1
                x += stepX
            }
            y += stepY
        }

        return HistogramData(red: r, green: g, blue: b, luminance: l)
    }

    var maxCount: Int {
        let allChannels = red + green + blue
        return allChannels.max() ?? 1
    }

    func normalized(channel: KeyPath<HistogramData, [Int]>) -> [Double] {
        let ch = self[keyPath: channel]
        let maxVal = Double(max(1, maxCount))
        return ch.map { Double($0) / maxVal }
    }
}
