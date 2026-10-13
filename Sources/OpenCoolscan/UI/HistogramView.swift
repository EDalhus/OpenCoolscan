import SwiftUI

struct HistogramView: View {
    let histogram: HistogramData
    @State private var showChannels = true

    var body: some View {
        Canvas { ctx, size in
            let maxVal = Double(histogram.maxCount)
            guard maxVal > 0 else { return }

            // Luminance (gray fill underneath)
            let lumPath = histogramPath(data: histogram.luminance, size: size, maxVal: maxVal)
            ctx.fill(lumPath, with: .color(.white.opacity(0.15)))

            if showChannels {
                // Red channel
                let rPath = histogramPath(data: histogram.red, size: size, maxVal: maxVal)
                ctx.stroke(rPath, with: .color(.red.opacity(0.6)), lineWidth: 1)

                // Green channel
                let gPath = histogramPath(data: histogram.green, size: size, maxVal: maxVal)
                ctx.stroke(gPath, with: .color(.green.opacity(0.6)), lineWidth: 1)

                // Blue channel
                let bPath = histogramPath(data: histogram.blue, size: size, maxVal: maxVal)
                ctx.stroke(bPath, with: .color(.blue.opacity(0.6)), lineWidth: 1)
            }

            // Axes
            ctx.stroke(
                Path { p in
                    p.move(to: CGPoint(x: 0, y: size.height))
                    p.addLine(to: CGPoint(x: size.width, y: size.height))
                },
                with: .color(.white.opacity(0.3)),
                lineWidth: 1
            )
        }
        .background(Color(white: 0.08))
        .cornerRadius(4)
        .overlay(alignment: .topTrailing) {
            Button(action: { showChannels.toggle() }) {
                Text(showChannels ? "RGB" : "Lum")
                    .font(.system(size: 9))
                    .padding(3)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(3)
            }
            .buttonStyle(.plain)
            .padding(4)
        }
    }

    private func histogramPath(data: [Int], size: CGSize, maxVal: Double) -> Path {
        let binCount = data.count
        let binWidth = size.width / CGFloat(binCount)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height))
        for (i, val) in data.enumerated() {
            let x = CGFloat(i) * binWidth
            let h = CGFloat(Double(val) / maxVal) * size.height
            path.addLine(to: CGPoint(x: x, y: size.height - h))
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        return path
    }
}
