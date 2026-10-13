import SwiftUI
import AppKit
import CoolscanKit

// MARK: - Tool Palette section contents (laid out after the Nikon Scan 4 reference)

extension Notification.Name {
    static let nikonRedrawRequested = Notification.Name("nikonRedrawRequested")
}

private func redraw() {
    NotificationCenter.default.post(name: .nikonRedrawRequested, object: nil)
}

private func showHelp(_ title: String, _ text: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = text
    alert.runModal()
}

/// Capsule button sized like the palette's Help / Reset / Redraw buttons.
private struct PaletteButton: View {
    let title: String
    var width: CGFloat = 58
    var enabled = true
    let action: () -> Void

    var body: some View {
        AquaPushButton(title: title, disabled: !enabled, action: action)
            .frame(width: width, height: 17)
    }
}

private struct PaletteLabel: View {
    let text: String
    var enabled = true
    init(_ text: String, enabled: Bool = true) { self.text = text; self.enabled = enabled }
    var body: some View {
        Text(text)
            .font(.lucida(11.5))
            .foregroundColor(enabled ? Color(hex: 0x2A2A2A) : Color(hex: 0xAAAAAA))
    }
}

// MARK: Layout Tools (rotate / flip — applied to previews, scans and saved files)

struct LayoutToolsContent: View {
    @EnvironmentObject var settings: ScanSettings
    @EnvironmentObject var scanner: ScannerManager

    private var current: FrameOrientation { settings.orientation(for: scanner.selectedFrame) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AquaBevelButton(systemImage: "rotate.left", size: 26, help: "Rotate 90° left") { change { $0.rotate(by: -90) } }
                AquaBevelButton(systemImage: "rotate.right", size: 26, help: "Rotate 90° right") { change { $0.rotate(by: 90) } }
                AquaBevelButton(systemImage: "arrow.triangle.2.circlepath", size: 26, help: "Rotate 180°") { change { $0.rotate(by: 180) } }
                AquaBevelButton(systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right", size: 26,
                                pressed: current.swapsAxes ? current.flipVertical : current.flipHorizontal,
                                help: "Flip horizontal") { change { $0.flipDisplayHorizontal() } }
                AquaBevelButton(systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down", size: 26,
                                pressed: current.swapsAxes ? current.flipHorizontal : current.flipVertical,
                                help: "Flip vertical") { change { $0.flipDisplayVertical() } }
            }
            .frame(maxWidth: .infinity)

            PaletteLabel(summary)

            AquaCheckbox(title: "Apply to all frames", isOn: $settings.orientationAppliesToAll)

            HStack {
                PaletteButton(title: "Help") {
                    showHelp("Layout Tools", "Rotates or mirrors the image. The orientation is shown in the preview and thumbnails and is applied when scans are saved, so files come out the right way up.\n\nWith “Apply to all frames” off, only the selected frame changes.")
                }
                Spacer()
                PaletteButton(title: "Reset") { change { $0 = FrameOrientation() } }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var summary: String {
        var parts = ["Rotation: \(current.rotation)°"]
        if current.flipHorizontal || current.flipVertical { parts.append("Mirrored") }
        let scope = settings.orientationAppliesToAll ? "all frames" : "frame \(scanner.selectedFrame + 1)"
        return parts.joined(separator: " · ") + " — " + scope
    }

    private func change(_ body: (inout FrameOrientation) -> Void) {
        settings.updateOrientation(frame: scanner.selectedFrame, body)
    }
}

// MARK: Curves

struct CurvesContent: View {
    @EnvironmentObject var settings: ScanSettings
    let histogram: HistogramData
    @State private var channel: Channel = .rgb
    @State private var hoverInput: Int?

    enum Channel: Hashable { case rgb, red, green, blue }

    var body: some View {
        VStack(spacing: 6) {
            AquaSegmented(options: [(Channel.rgb, "RGB"), (.red, "R"), (.green, "G"), (.blue, "B")],
                          selection: $channel)
                .frame(width: 108)

            CurveEditorView(curve: curveBinding, histogram: histogramData, color: curveColor) { hoverInput = $0 }
                .frame(width: 186, height: 186)

            HStack {
                PaletteLabel("Input: \(displayInput)")
                Spacer()
                PaletteLabel("Output: \(displayOutput)")
            }
            .padding(.horizontal, 18)

            AquaSliderRow(label: "Midtone", value: midtone, range: -100...100, labelWidth: 72)

            HStack {
                PaletteButton(title: "Auto Contrast", width: 92, action: autoContrast)
                Spacer()
                PaletteButton(title: "Reset") {
                    settings.curves = Curves()
                    settings.gamma = 1
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var curveBinding: Binding<ToneCurve> {
        switch channel {
        case .rgb:   return $settings.curves.composite
        case .red:   return $settings.curves.red
        case .green: return $settings.curves.green
        case .blue:  return $settings.curves.blue
        }
    }

    private var curveColor: Color {
        switch channel {
        case .rgb: return .black
        case .red: return Color(hex: 0xC8201A)
        case .green: return Color(hex: 0x1E8A1E)
        case .blue: return Color(hex: 0x2050C8)
        }
    }

    private var histogramData: [Int] {
        switch channel {
        case .rgb:   return histogram.luminance
        case .red:   return histogram.red
        case .green: return histogram.green
        case .blue:  return histogram.blue
        }
    }

    private var displayInput: Int { hoverInput ?? 128 }
    private var displayOutput: Int {
        Int((curveBinding.wrappedValue.output(for: Double(displayInput) / 255) * 255).rounded())
    }

    /// Midtone maps to gamma: 0 ↔ 1.0, ±100 ↔ 4× / ¼.
    private var midtone: Binding<Double> {
        Binding(
            get: { (50 * log2(settings.gamma)).rounded() },
            set: { settings.gamma = min(3, max(0.25, pow(2, $0 / 50))) }
        )
    }

    /// Stretches the 0.5 % – 99.5 % histogram range to full scale.
    private func autoContrast() {
        let data = histogramData
        let total = data.reduce(0, +)
        guard total > 0 else { return }
        let cutoff = Int(Double(total) * 0.005)
        var acc = 0, lo = 0, hi = 255
        for i in 0..<data.count { acc += data[i]; if acc > cutoff { lo = i; break } }
        acc = 0
        for i in stride(from: data.count - 1, through: 0, by: -1) { acc += data[i]; if acc > cutoff { hi = i; break } }
        guard hi - lo > 8 else { return }
        curveBinding.wrappedValue = ToneCurve(points: [
            CurvePoint(input: 0, output: 0),
            CurvePoint(input: Double(lo) / 255, output: 0),
            CurvePoint(input: Double(hi) / 255, output: 1),
            CurvePoint(input: 1, output: 1)
        ])
    }
}

// MARK: Color Balance

struct ColorBalanceContent: View {
    @EnvironmentObject var settings: ScanSettings

    var body: some View {
        VStack(spacing: 1) {
            AquaSliderRow(label: "Brightness", value: $settings.colorBrightness, range: -100...100)
            AquaSliderRow(label: "Contrast", value: Binding(
                get: { (settings.contrast * 100 / 3).rounded() },
                set: { settings.contrast = $0 * 3 / 100 }
            ), range: -100...100)
            AquaSliderRow(label: "Red", value: Binding(get: { settings.colorBalance.x },
                                                       set: { settings.colorBalance.x = $0 }), range: -100...100)
            AquaSliderRow(label: "Green", value: Binding(get: { settings.colorBalance.y },
                                                         set: { settings.colorBalance.y = $0 }), range: -100...100)
            AquaSliderRow(label: "Blue", value: Binding(get: { settings.colorBalance.z },
                                                        set: { settings.colorBalance.z = $0 }), range: -100...100)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

// MARK: Unsharp Mask

struct UnsharpMaskContent: View {
    @EnvironmentObject var settings: ScanSettings

    var body: some View {
        VStack(spacing: 1) {
            AquaSliderRow(label: "Intensity", value: $settings.usmIntensity, range: 0...100)
            AquaSliderRow(label: "Halo width", value: $settings.usmHaloWidth, range: 0...100)
            AquaSliderRow(label: "Threshold", value: $settings.usmThreshold, range: 0...100)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

// MARK: Digital ICE⁴ Advanced

struct DigitalICEContent: View {
    @EnvironmentObject var settings: ScanSettings
    @EnvironmentObject var scanner: ScannerManager
    @State private var lastMode: DigitalICE = .normal
    @State private var showMore = true

    private var supported: Bool { scanner.connectedScanner?.model.supportsDigitalICE ?? true }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            AquaCheckbox(title: "Enable Digital ICE", isOn: Binding(
                get: { settings.digitalICE != .off },
                set: { on in
                    if on { settings.digitalICE = lastMode } else {
                        lastMode = settings.digitalICE == .off ? lastMode : settings.digitalICE
                        settings.digitalICE = .off
                    }
                }
            ), enabled: supported)

            HStack(spacing: 8) {
                PaletteLabel("Mode", enabled: settings.digitalICE != .off)
                AquaBluePopup(label: modeTitle(settings.digitalICE == .off ? lastMode : settings.digitalICE),
                              enabled: settings.digitalICE != .off) {
                    [DigitalICE.normal, .fine].map { mode in
                        PopupMenu.Item(title: modeTitle(mode), checked: settings.digitalICE == mode) {
                            settings.digitalICE = mode
                            lastMode = mode
                        }
                    }
                }
            }

            if showMore {
                AquaCheckbox(title: "Enable Post Processing", isOn: $settings.icePostProcessing)
                VStack(spacing: 1) {
                    AquaSliderRow(label: "Digital ROC", value: $settings.rocLevel, range: 0...10,
                                  enabled: settings.icePostProcessing)
                    AquaSliderRow(label: "Digital GEM", value: $settings.gemLevel, range: 0...4,
                                  enabled: settings.icePostProcessing)
                }

                AquaCheckbox(title: "Enable Digital DEE", isOn: $settings.deeEnabled)
                PaletteLabel("Shadow adjustment", enabled: settings.deeEnabled)
                AquaSliderControl(value: $settings.deeShadow, range: 0...100, enabled: settings.deeEnabled)
            }

            HStack {
                PaletteButton(title: showMore ? "More>>" : "<<Less") { showMore.toggle() }
                Spacer()
                PaletteButton(title: "Redraw", action: redraw)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func modeTitle(_ mode: DigitalICE) -> String {
        mode == .fine ? "On (Fine)" : "On (Normal)"
    }
}

// MARK: Analog Gain

struct AnalogGainContent: View {
    @EnvironmentObject var settings: ScanSettings

    var body: some View {
        VStack(spacing: 1) {
            AquaSliderRow(label: "Master:", value: $settings.brightness, range: -2...2, step: 0.05, decimals: 2)
            AquaSliderRow(label: "Red:", value: channel(\.x), range: -2...2, step: 0.05, decimals: 2)
            AquaSliderRow(label: "Green:", value: channel(\.y), range: -2...2, step: 0.05, decimals: 2)
            AquaSliderRow(label: "Blue:", value: channel(\.z), range: -2...2, step: 0.05, decimals: 2)

            HStack {
                PaletteButton(title: "Help") {
                    showHelp("Analog Gain", "Adjusts exposure in EV stops. Master changes all channels; Red, Green and Blue change one channel each.")
                }
                Spacer()
                PaletteButton(title: "Reset") {
                    settings.brightness = 0
                    settings.analogGain = .zero
                }
                Spacer()
                PaletteButton(title: "Redraw", action: redraw)
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func channel(_ kp: WritableKeyPath<SIMD3<Double>, Double>) -> Binding<Double> {
        Binding(get: { settings.analogGain[keyPath: kp] }, set: { settings.analogGain[keyPath: kp] = $0 })
    }
}

// MARK: Scan Image Enhancer

struct ScanImageEnhancerContent: View {
    @EnvironmentObject var settings: ScanSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AquaCheckbox(title: "Enable Scan Image Enhancer", isOn: $settings.sieEnabled)
            HStack {
                Spacer()
                PaletteButton(title: "Redraw", action: redraw)
                Spacer()
                Spacer()
                PaletteButton(title: "Help") {
                    showHelp("Scan Image Enhancer", "Automatically corrects tone and color balance of the scanned image.")
                }
                Spacer()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

// MARK: Scanner Extras

struct ScannerExtrasContent: View {
    @EnvironmentObject var settings: ScanSettings
    @EnvironmentObject var scanner: ScannerManager

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            PaletteLabel("Pixel Data Size · Scan bit depth")
            AquaBluePopup(label: settings.bitDepth == .bit8 ? "8" : "14") {
                [
                    PopupMenu.Item(title: "8", checked: settings.bitDepth == .bit8) { settings.bitDepth = .bit8 },
                    PopupMenu.Item(title: "14", checked: settings.bitDepth == .bit14) { settings.bitDepth = .bit14 }
                ]
            }

            PaletteLabel("Manual Focus Adjustment").padding(.top, 4)
            AquaSliderControl(value: Binding(
                get: { Double(settings.manualFocusSteps) },
                set: { settings.manualFocusSteps = Int($0) }
            ), range: 0...500)
            centeredButton("Help") {
                showHelp("Manual Focus Adjustment", "Sets the focus position used when autofocus is turned off (Scanner ▸ Auto Focus).")
            }

            PaletteLabel("Multi Sample Scanning").padding(.top, 4)
            AquaBluePopup(label: multiSampleTitle) {
                [1, 2, 4, 8, 16].map { n in
                    PopupMenu.Item(title: n == 1 ? "Normal (1x)" : "\(n)x",
                                   checked: n == (settings.multiScan ? settings.multiScanCount : 1)) {
                        settings.multiScan = n > 1
                        if n > 1 { settings.multiScanCount = n }
                    }
                }
            }
            centeredButton("Help") {
                showHelp("Multi Sample Scanning", "Scans each line several times and averages the result to reduce noise. Higher values take longer.")
            }

            PaletteLabel("Strip Film Offset").padding(.top, 4)
            AquaSliderControl(value: Binding(
                get: { Double(settings.alignmentOffset) },
                set: { settings.alignmentOffset = Int($0) }
            ), range: -200...200)

            centeredButton("Reload Thumbnail", enabled: scanner.connectedScanner != nil && !scanner.isBusy) {
                Task { await scanner.autoPreviewAllFrames(settings: settings) }
            }
            .padding(.top, 2)
            centeredButton("Calibrate") {
                showHelp("Calibrate", "Coolscan scanners calibrate themselves when powered on and before each scan. No manual calibration is needed.")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var multiSampleTitle: String {
        settings.multiScan ? "\(settings.multiScanCount)x" : "Normal (1x)"
    }

    private func centeredButton(_ title: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        HStack {
            Spacer()
            PaletteButton(title: title, width: 120, enabled: enabled, action: action)
            Spacer()
        }
    }
}
