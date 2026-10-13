import SwiftUI

struct CurveEditorView: View {
    @Binding var curve: ToneCurve
    var color: Color = .white
    @State private var draggingIndex: Int?
    @State private var lastTapTime: Date = .distantPast

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Canvas { ctx, size in
                    let gray = GraphicsContext.Shading.color(Color.white.opacity(0.1))
                    let steps = 4
                    for i in 0...steps {
                        let x = size.width * CGFloat(i) / CGFloat(steps)
                        let y = size.height * CGFloat(i) / CGFloat(steps)
                        ctx.stroke(Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) }, with: gray, lineWidth: 0.5)
                        ctx.stroke(Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)) }, with: gray, lineWidth: 0.5)
                    }
                    // Diagonal reference: bottom-left → top-right (linear identity)
                    ctx.stroke(
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: size.height))
                            p.addLine(to: CGPoint(x: size.width, y: 0))
                        },
                        with: GraphicsContext.Shading.color(Color.white.opacity(0.2)),
                        lineWidth: 0.5
                    )
                }
                .background(Color(white: 0.12))
                .cornerRadius(4)

                Canvas { ctx, size in
                    let pts = curve.points.sorted { $0.input < $1.input }
                    guard pts.count >= 2 else { return }

                    var path = Path()
                    path.move(to: curvePoint(pts[0], size: size))
                    for i in 1..<pts.count {
                        path.addLine(to: curvePoint(pts[i], size: size))
                    }
                    ctx.stroke(path, with: .color(color.opacity(0.9)), lineWidth: 1.5)
                }

                ForEach(Array(curve.points.enumerated()), id: \.offset) { idx, pt in
                    let ptPos = CGPoint(
                        x: pt.input * geo.size.width,
                        y: (1 - pt.output) * geo.size.height
                    )
                    Circle()
                        .foregroundColor(draggingIndex == idx ? Color.white : color)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1))
                        .frame(width: 9, height: 9)
                        .position(ptPos)
                        .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                            draggingIndex = idx
                            let newX = max(0, min(1, drag.location.x / geo.size.width))
                            let newY = max(0, min(1, 1 - drag.location.y / geo.size.height))
                            // Keep endpoints pinned in X so the curve stays defined
                            if idx == 0 {
                                curve.points[idx] = CurvePoint(input: 0, output: newY)
                            } else if idx == curve.points.count - 1 {
                                curve.points[idx] = CurvePoint(input: 1, output: newY)
                            } else {
                                curve.points[idx] = CurvePoint(input: newX, output: newY)
                            }
                        }.onEnded { _ in draggingIndex = nil })
                        .contextMenu {
                            if idx > 0 && idx < curve.points.count - 1 {
                                Button("Remove Point") {
                                    curve.points.remove(at: idx)
                                }
                            }
                        }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { loc in
                let now = Date()
                // Require a quick second tap to add a point (avoids spam)
                if now.timeIntervalSince(lastTapTime) < 0.35 {
                    let x = loc.x / geo.size.width
                    let y = 1 - loc.y / geo.size.height
                    curve.points.append(CurvePoint(input: x, output: y))
                    lastTapTime = .distantPast
                } else {
                    lastTapTime = now
                }
            }
        }
    }

    private func curvePoint(_ pt: CurvePoint, size: CGSize) -> CGPoint {
        CGPoint(x: pt.input * size.width, y: (1 - pt.output) * size.height)
    }
}
