import SwiftUI
import AppKit

// MARK: - Palette (sampled from the Nikon Scan 4 design reference)

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue:  Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    static let aquaDesktop      = Color(hex: 0xB4B4B4)
    static let aquaWindow       = Color(hex: 0xE8E8E8)
    static let aquaTitleTop     = Color(hex: 0xEDEDED)
    static let aquaTitleBottom  = Color(hex: 0xD1D1D1)
    static let aquaEdge         = Color(hex: 0x7A7A7A)
    static let aquaSidePanel    = Color(hex: 0xAAAAAA)
    static let aquaFrameArea    = Color(hex: 0x868686)
    static let aquaInfo         = Color(hex: 0x4E4E4E)
    static let aquaInfoBorder   = Color(hex: 0x2E2E2E)
    static let aquaTeal         = Color(hex: 0x5FD3C6)
    static let aquaTealLabel    = Color(hex: 0x6CE2D5)
    static let aquaImageArea    = Color(hex: 0xA3A3A3)
    static let aquaSelection    = Color(hex: 0x4874D0)
    static let aquaRowAlt       = Color(hex: 0xF4F6FB)
    static let aquaText         = Color(hex: 0x111111)
    static let aquaTextDim      = Color(hex: 0x444444)
    static let aquaBadgeDone    = Color(hex: 0x4A8A3A)
    static let aquaBadgeActive  = Color(hex: 0x3F73D8)
    static let aquaBadgeWaiting = Color(hex: 0x262E42, opacity: 0.85)
}

// MARK: - Typography

extension Font {
    /// Lucida Grande — the Aqua-era system font used throughout the design.
    static func lucida(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "LucidaGrande-Bold" : "LucidaGrande", size: size)
    }
}

// MARK: - Window chrome

/// Gradient title bar with glossy traffic lights, as on Mac OS X 10.4.
struct AquaTitleBar: View {
    let title: String
    var height: CGFloat = 22
    var fontSize: CGFloat = 13
    var showsAllLights = true
    var onClose: () -> Void = {}
    var onMinimize: () -> Void = {}
    var onZoom: () -> Void = {}
    var onTitleClick: (() -> Void)? = nil

    var body: some View {
        ZStack {
            LinearGradient(colors: [.aquaTitleTop, .aquaTitleBottom], startPoint: .top, endPoint: .bottom)
            WindowDragArea()

            HStack(spacing: showsAllLights ? 8 : 0) {
                AquaLight(color: .red, diameter: height * 0.6, action: onClose)
                if showsAllLights {
                    AquaLight(color: .yellow, diameter: height * 0.6, action: onMinimize)
                    AquaLight(color: .green, diameter: height * 0.6, action: onZoom)
                }
                Spacer()
            }
            .padding(.leading, 8)

            Text(title)
                .font(.lucida(fontSize))
                .foregroundColor(.aquaText)
                .lineLimit(1)
                .padding(.horizontal, 70)
                .contentShape(Rectangle())
                .onTapGesture { onTitleClick?() }
        }
        .frame(height: height)
        .overlay(alignment: .bottom) { Color.aquaEdge.frame(height: 1) }
    }
}

struct AquaLight: View {
    enum Kind { case red, yellow, green }
    let color: Kind
    var diameter: CGFloat = 13
    let action: () -> Void

    private var base: (Color, Color) {
        switch color {
        case .red:    return (Color(hex: 0xF0685E), Color(hex: 0xB0201A))
        case .yellow: return (Color(hex: 0xF8D25A), Color(hex: 0xC08410))
        case .green:  return (Color(hex: 0x86D46A), Color(hex: 0x2F8A20))
        }
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(RadialGradient(colors: [base.0, base.1],
                                             center: UnitPoint(x: 0.5, y: 0.75),
                                             startRadius: 0, endRadius: diameter * 0.6))
                Circle().stroke(Color.black.opacity(0.45), lineWidth: 0.75)
                Ellipse()
                    .fill(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.05)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: diameter * 0.62, height: diameter * 0.42)
                    .offset(y: -diameter * 0.2)
            }
            .frame(width: diameter, height: diameter)
        }
        .buttonStyle(.plain)
    }
}

/// Body of a floating Aqua window (the NSWindow draws the drop shadow).
struct AquaWindow<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .background { Color.aquaWindow }
            .overlay(Rectangle().stroke(Color.black.opacity(0.35), lineWidth: 0.5))
    }
}

// MARK: - Window dragging

/// Lets custom title bars move the real NSWindow (and double-click zoom it).
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.zoom(nil)
            } else {
                window?.performDrag(with: event)
            }
        }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Popup menus

/// Shows a native NSMenu at the mouse location — used for the Aqua popups
/// so the controls can be drawn exactly like the design.
enum PopupMenu {
    struct Item {
        let title: String
        var checked = false
        var enabled = true
        let action: () -> Void
    }

    @MainActor
    static func show(_ items: [Item]) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let target = Target(items: items)
        for (i, item) in items.enumerated() {
            let mi = NSMenuItem(title: item.title, action: #selector(Target.fire(_:)), keyEquivalent: "")
            mi.tag = i
            mi.target = target
            mi.state = item.checked ? .on : .off
            mi.isEnabled = item.enabled
            menu.addItem(mi)
        }
        objc_setAssociatedObject(menu, &Target.key, target, .OBJC_ASSOCIATION_RETAIN)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private final class Target: NSObject {
        static var key = 0
        let items: [Item]
        init(items: [Item]) { self.items = items }
        @objc func fire(_ sender: NSMenuItem) { items[sender.tag].action() }
    }
}

// MARK: - Controls

/// Square bevel button (eject / thumbnails / invert / zoom).
struct AquaBevelButton: View {
    let systemImage: String
    var size: CGFloat = 30
    var pressed = false
    var disabled = false
    var help = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(
                        colors: pressed ? [Color(hex: 0x9A9A9A), Color(hex: 0xB8B8B8)]
                                        : [Color(hex: 0xF4F4F4), Color(hex: 0xC9C9C9)],
                        startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color(hex: 0x5A5A5A), lineWidth: 1)
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundColor(disabled ? Color(hex: 0x8A8A8A) : Color(hex: 0x1A1A1A))
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.35), radius: 0.5, x: 1, y: 1.5)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
    }
}

/// Aqua popup: list glyph, label, and a separate arrow segment.
struct AquaPopup: View {
    let label: String
    var height: CGFloat = 19
    let items: () -> [PopupMenu.Item]

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(hex: 0x333333))
                .padding(.horizontal, 5)
            Text(label)
                .font(.lucida(12))
                .foregroundColor(.aquaText)
                .lineLimit(1)
            Spacer(minLength: 2)
            ZStack {
                LinearGradient(colors: [Color(hex: 0xF6F6F6), Color(hex: 0xC8C8C8)],
                               startPoint: .top, endPoint: .bottom)
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 8))
                    .foregroundColor(Color(hex: 0x222222))
            }
            .frame(width: height + 2)
            .overlay(alignment: .leading) { Color(hex: 0x6A6A6A).frame(width: 1) }
        }
        .frame(height: height)
        .background(LinearGradient(colors: [Color(hex: 0xFAFAFA), Color(hex: 0xDADADA)],
                                   startPoint: .top, endPoint: .bottom))
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color(hex: 0x5A5A5A), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .shadow(color: .black.opacity(0.3), radius: 0.5, x: 0, y: 1)
        .contentShape(Rectangle())
        .onTapGesture { PopupMenu.show(items()) }
    }
}

/// Glossy sphere button (Preview / Scan / Prefs / Help / Tools).
struct GlossyOrb: View {
    let color: Color
    let dark: Color
    var diameter: CGFloat = 50
    var ring = true
    var disabled = false
    var badge = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if ring {
                    Circle()
                        .fill(LinearGradient(colors: [Color(hex: 0x3A3A3A), Color(hex: 0x8C8C8C)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: diameter + 6, height: diameter + 6)
                }
                Circle()
                    .fill(RadialGradient(colors: [color, dark],
                                         center: UnitPoint(x: 0.5, y: 0.78),
                                         startRadius: 0, endRadius: diameter * 0.62))
                    .frame(width: diameter, height: diameter)
                Circle()
                    .stroke(Color.black.opacity(0.35), lineWidth: 1)
                    .frame(width: diameter, height: diameter)
                Ellipse()
                    .fill(LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.0)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: diameter * 0.7, height: diameter * 0.45)
                    .offset(y: -diameter * 0.22)
                if badge {
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: diameter * 0.3))
                        .foregroundColor(Color(hex: 0xC9A8F0))
                        .shadow(color: .black.opacity(0.4), radius: 0.5)
                        .offset(x: diameter * 0.42, y: diameter * 0.42)
                }
            }
            .saturation(disabled ? 0.25 : 1)
            .opacity(disabled ? 0.6 : 1)
            .shadow(color: .black.opacity(0.3), radius: 1.5, x: 0, y: 1.5)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

/// Rounded Aqua push button ("Stop").
struct AquaPushButton: View {
    let title: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.lucida(12))
                .foregroundColor(disabled ? Color(hex: 0x9A9A9A) : .aquaText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Capsule().fill(LinearGradient(colors: [Color(hex: 0xFBFBFB), Color(hex: 0xDCDCDC)],
                                                          startPoint: .top, endPoint: .bottom)))
                .overlay(Capsule().stroke(Color(hex: disabled ? 0xB0B0B0 : 0x7A7A7A), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

/// Blue barber-pole Aqua progress bar.
struct AquaProgressBar: View {
    let value: Double   // 0...1
    var animating = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .leading) {
                Capsule().fill(LinearGradient(colors: [Color(hex: 0xD4D4D4), Color(hex: 0xF6F6F6)],
                                              startPoint: .top, endPoint: .bottom))
                if value > 0 {
                    TimelineView(.animation(paused: !animating)) { tl in
                        let phase = CGFloat(tl.date.timeIntervalSinceReferenceDate * 14)
                            .truncatingRemainder(dividingBy: h * 1.6)
                        Canvas { ctx, size in
                            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                                     with: .linearGradient(Gradient(colors: [Color(hex: 0xB9D0F8), Color(hex: 0x5D8EE6), Color(hex: 0x3D74DC)]),
                                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                            var x = -size.height * 2 + phase
                            while x < size.width + size.height {
                                var p = Path()
                                p.move(to: CGPoint(x: x, y: size.height))
                                p.addLine(to: CGPoint(x: x + size.height * 0.8, y: 0))
                                p.addLine(to: CGPoint(x: x + size.height * 1.6, y: 0))
                                p.addLine(to: CGPoint(x: x + size.height * 0.8, y: size.height))
                                p.closeSubpath()
                                ctx.fill(p, with: .color(.white.opacity(0.32)))
                                x += size.height * 1.6
                            }
                        }
                    }
                    .frame(width: max(h, w * min(1, value)))
                    .clipShape(Capsule())
                }
                Capsule().stroke(Color(hex: 0x8A8A8A), lineWidth: 1)
            }
        }
    }
}

/// Classic Aqua tab (Queue/Log, Processed/Natural).
struct AquaTab: View {
    let title: String
    let selected: Bool
    var fontSize: CGFloat = 12
    let action: () -> Void

    var body: some View {
        Text(title)
            .font(.lucida(fontSize))
            .foregroundColor(.aquaText)
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity)
            .background(
                UnevenTopRoundedRect(radius: 5)
                    .fill(LinearGradient(colors: selected ? [Color(hex: 0xFFFFFF), Color(hex: 0xE6E6E6)]
                                                          : [Color(hex: 0xE2E2E2), Color(hex: 0xC4C4C4)],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(UnevenTopRoundedRect(radius: 5).stroke(Color(hex: 0x7A7A7A), lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }
}

/// Rectangle with only the top corners rounded (SwiftUI's own version needs macOS 14).
struct UnevenTopRoundedRect: Shape {
    var radius: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + radius))
        p.addQuadCurve(to: CGPoint(x: r.minX + radius, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + radius), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        return p
    }
}

// MARK: - Tool Palette controls

/// Small square arrow button (◀ / ▶) at either end of an Aqua slider.
struct AquaStepButton: View {
    let left: Bool
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                LinearGradient(colors: [Color(hex: 0xFFFFFF), Color(hex: 0xDADADA)], startPoint: .top, endPoint: .bottom)
                Rectangle().stroke(Color(hex: enabled ? 0x6A6A6A : 0xB0B0B0), lineWidth: 1)
                Image(systemName: left ? "arrowtriangle.left.fill" : "arrowtriangle.right.fill")
                    .font(.system(size: 6))
                    .foregroundColor(Color(hex: enabled ? 0x222222 : 0xAAAAAA))
            }
            .frame(width: 12, height: 12)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Thin track with a glossy blue knob.
struct AquaSliderTrack: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var enabled = true

    var body: some View {
        GeometryReader { geo in
            let knob: CGFloat = 15
            let w = geo.size.width - knob
            let frac = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: [Color(hex: 0xB9B9B9), Color(hex: 0xEDEDED)], startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().stroke(Color(hex: enabled ? 0x8A8A8A : 0xBDBDBD), lineWidth: 0.75))
                    .frame(height: 4.5)
                    .padding(.horizontal, 2)
                AquaKnob(enabled: enabled)
                    .frame(width: knob, height: knob)
                    .offset(x: w * CGFloat(min(1, max(0, frac))))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                guard enabled, w > 0 else { return }
                let f = Double(min(1, max(0, (g.location.x - knob / 2) / w)))
                let raw = range.lowerBound + f * (range.upperBound - range.lowerBound)
                value = (raw / step).rounded() * step
            })
        }
    }
}

struct AquaKnob: View {
    var enabled = true
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(
                colors: enabled ? [Color(hex: 0xB8D6FA), Color(hex: 0x3F7EDB)] : [Color(hex: 0xF4F4F4), Color(hex: 0xC8C8C8)],
                center: UnitPoint(x: 0.5, y: 0.8), startRadius: 0, endRadius: 10))
            Circle().stroke(Color(hex: enabled ? 0x2F5EA8 : 0xA8A8A8), lineWidth: 0.75)
            Ellipse()
                .fill(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                .frame(width: 9, height: 6)
                .offset(y: -3.5)
        }
        .shadow(color: .black.opacity(enabled ? 0.3 : 0.1), radius: 0.8, y: 0.8)
    }
}

/// White numeric box at the right of a slider row.
struct AquaValueField: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var decimals = 0
    var enabled = true

    var body: some View {
        TextField("", value: Binding(
            get: { value },
            set: { value = min(range.upperBound, max(range.lowerBound, $0)) }
        ), format: .number.precision(.fractionLength(decimals)).grouping(.never)
            .locale(Locale(identifier: "en_US_POSIX")))
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .font(.lucida(11.5))
            .foregroundColor(enabled ? .aquaText : Color(hex: 0xAAAAAA))
            .padding(.horizontal, 3)
            .frame(width: 33, height: 15)
            .background { Color.white }
            .overlay(Rectangle().stroke(Color(hex: enabled ? 0x7A7A7A : 0xC0C0C0), lineWidth: 1))
            .disabled(!enabled)
    }
}

/// ◀ ——●—— ▶ [value]
struct AquaSliderControl: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var decimals = 0
    var enabled = true

    var body: some View {
        HStack(spacing: 2) {
            AquaStepButton(left: true, enabled: enabled) { value = max(range.lowerBound, value - step) }
            AquaSliderTrack(value: $value, range: range, step: step, enabled: enabled)
                .frame(height: 16)
            AquaStepButton(left: false, enabled: enabled) { value = min(range.upperBound, value + step) }
            AquaValueField(value: $value, range: range, decimals: decimals, enabled: enabled)
                .padding(.leading, 3)
        }
    }
}

/// Label on the left, slider control on the right.
struct AquaSliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var decimals = 0
    var enabled = true
    var labelWidth: CGFloat = 72

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.lucida(11.5))
                .foregroundColor(enabled ? Color(hex: 0x2A2A2A) : Color(hex: 0xAAAAAA))
                .lineLimit(1)
                .frame(width: labelWidth, alignment: .leading)
            AquaSliderControl(value: $value, range: range, step: step, decimals: decimals, enabled: enabled)
        }
        .frame(height: 20)
    }
}

/// Aqua checkbox — blue when checked.
struct AquaCheckbox: View {
    let title: String
    @Binding var isOn: Bool
    var enabled = true

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(LinearGradient(
                            colors: isOn ? [Color(hex: 0xA9CBF6), Color(hex: 0x4A86DE)] : [Color(hex: 0xFFFFFF), Color(hex: 0xE2E2E2)],
                            startPoint: .top, endPoint: .bottom))
                    RoundedRectangle(cornerRadius: 2.5)
                        .stroke(Color(hex: isOn ? 0x3A68B0 : 0x7A7A7A), lineWidth: 1)
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(Color(hex: 0x10204A))
                    }
                }
                .frame(width: 13, height: 13)
                Text(title)
                    .font(.lucida(12))
                    .foregroundColor(enabled ? .aquaText : Color(hex: 0xAAAAAA))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Rounded popup with a blue up/down arrow segment on the right.
struct AquaBluePopup: View {
    let label: String
    var enabled = true
    let items: () -> [PopupMenu.Item]

    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.lucida(12))
                .foregroundColor(enabled ? .aquaText : Color(hex: 0xAAAAAA))
                .lineLimit(1)
                .padding(.leading, 7)
            Spacer(minLength: 2)
            ZStack {
                LinearGradient(colors: [Color(hex: 0x9CC2F5), Color(hex: 0x3D78DA)], startPoint: .top, endPoint: .bottom)
                VStack(spacing: 1) {
                    Image(systemName: "arrowtriangle.up.fill")
                    Image(systemName: "arrowtriangle.down.fill")
                }
                .font(.system(size: 5))
                .foregroundColor(.white)
            }
            .frame(width: 15)
        }
        .frame(height: 16)
        .background { LinearGradient(colors: [Color(hex: 0xFFFFFF), Color(hex: 0xE8E8E8)], startPoint: .top, endPoint: .bottom) }
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(hex: 0x7A7A7A), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { if enabled { PopupMenu.show(items()) } }
    }
}

/// RGB / R / G / B segmented control.
struct AquaSegmented<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { idx, opt in
                let selected = opt.0 == selection
                Text(opt.1)
                    .font(.lucida(11))
                    .foregroundColor(selected ? .white : .aquaText)
                    .frame(width: 26, height: 14)
                    .background {
                        LinearGradient(colors: selected ? [Color(hex: 0x8DB8F4), Color(hex: 0x3F7ADB)]
                                                        : [Color(hex: 0xFFFFFF), Color(hex: 0xE0E0E0)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                    .overlay(alignment: .leading) {
                        if idx > 0 { Color(hex: 0x7A7A7A).frame(width: 1) }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selection = opt.0 }
            }
        }
        .overlay(Rectangle().stroke(Color(hex: 0x6A6A6A), lineWidth: 1))
    }
}
