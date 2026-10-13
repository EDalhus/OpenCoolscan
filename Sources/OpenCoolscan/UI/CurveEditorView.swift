import SwiftUI

/// Nikon Scan–style curve editor: white grid, gray histogram, black curve,
/// square handles. A linear curve shows a midpoint handle that adds a point when dragged.
struct CurveEditorView: View {
    @Binding var curve: ToneCurve
    var histogram: [Int] = []
    var color: Color = .black
    /// Reports the input level (0–255) under the pointer, or nil when outside.
    var onHover: (Int?) -> Void = { _ in }

    @State private var draggingIndex: Int?

    private var handles: [CurvePoint] {
        let sorted = curve.points.sorted { $0.input < $1.input }
        if sorted.count == 2 {
            return [CurvePoint(input: 0.5, output: curve.output(for: 0.5))]
        }
        return Array(sorted.dropFirst().dropLast())
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))

                    // Histogram (smoothed)
                    let maxVal = Double(histogram.max() ?? 0)
                    if maxVal > 0, histogram.count > 1 {
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: size.height))
                        let n = histogram.count
                        for i in 0..<n {
                            let lo = max(0, i - 3), hi = min(n - 1, i + 3)
                            let avg = Double(histogram[lo...hi].reduce(0, +)) / Double(hi - lo + 1)
                            let x = size.width * CGFloat(i) / CGFloat(n - 1)
                            path.addLine(to: CGPoint(x: x, y: size.height * (1 - CGFloat(avg / maxVal) * 0.85)))
                        }
                        path.addLine(to: CGPoint(x: size.width, y: size.height))
                        path.closeSubpath()
                        ctx.fill(path, with: .color(Color(hex: 0xC6C6C6)))
                    }

                    // Grid
                    var grid = Path()
                    for i in 1..<4 {
                        let x = size.width * CGFloat(i) / 4, y = size.height * CGFloat(i) / 4
                        grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height))
                        grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    ctx.stroke(grid, with: .color(Color(hex: 0xD8D8D8)), lineWidth: 1)

                    // Curve
                    var c = Path()
                    let steps = 128
                    for i in 0...steps {
                        let input = Double(i) / Double(steps)
                        let p = CGPoint(x: size.width * input, y: size.height * (1 - curve.output(for: input)))
                        if i == 0 { c.move(to: p) } else { c.addLine(to: p) }
                    }
                    ctx.stroke(c, with: .color(color), lineWidth: 1.5)
                }

                ForEach(Array(handles.enumerated()), id: \.offset) { _, pt in
                    Rectangle()
                        .fill(Color.white)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                        .frame(width: 7, height: 7)
                        .position(x: pt.input * size.width, y: (1 - pt.output) * size.height)
                        .allowsHitTesting(false)
                }
            }
            .overlay(Rectangle().stroke(Color(hex: 0x6A6A6A), lineWidth: 1))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let x = max(0, min(1, drag.location.x / size.width))
                        let y = max(0, min(1, 1 - drag.location.y / size.height))
                        if draggingIndex == nil {
                            draggingIndex = handleIndex(near: drag.startLocation, size: size)
                        }
                        guard let idx = draggingIndex else { return }
                        if idx == 0 {
                            curve.points[idx] = CurvePoint(input: 0, output: y)
                        } else if idx == curve.points.count - 1 {
                            curve.points[idx] = CurvePoint(input: 1, output: y)
                        } else {
                            curve.points[idx] = CurvePoint(input: x, output: y)
                        }
                        onHover(Int((x * 255).rounded()))
                    }
                    .onEnded { _ in draggingIndex = nil }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): onHover(Int((max(0, min(1, p.x / size.width)) * 255).rounded()))
                case .ended: onHover(nil)
                }
            }
            .contextMenu {
                Button("Reset Curve") { curve = .linear }
            }
        }
    }

    /// Picks the closest existing point, or inserts a new one on the curve.
    private func handleIndex(near p: CGPoint, size: CGSize) -> Int? {
        curve.points.sort { $0.input < $1.input }
        let pts = curve.points.map { CGPoint(x: $0.input * size.width, y: (1 - $0.output) * size.height) }
        if let (i, d) = pts.enumerated().map({ ($0.offset, hypot($0.element.x - p.x, $0.element.y - p.y)) })
            .min(by: { $0.1 < $1.1 }), d < 10 {
            return i
        }
        let input = max(0.01, min(0.99, p.x / size.width))
        curve.points.append(CurvePoint(input: input, output: curve.output(for: input)))
        curve.points.sort { $0.input < $1.input }
        return curve.points.firstIndex { $0.input == input }
    }
}
