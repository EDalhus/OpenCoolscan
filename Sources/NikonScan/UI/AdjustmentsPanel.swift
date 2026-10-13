import SwiftUI

// MARK: - Tool Palette section contents

/// Curves (+ histogram for reference)
struct CurvesContent: View {
    @EnvironmentObject var settings: ScanSettings
    let histogram: HistogramData
    @State private var activeChannel: CurveChannel = .composite

    enum CurveChannel: String, CaseIterable {
        case composite = "RGB"
        case red   = "R"
        case green = "G"
        case blue  = "B"

        var color: Color {
            switch self {
            case .composite: return .white
            case .red:   return .red
            case .green: return .green
            case .blue:  return .blue
            }
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            Picker("", selection: $activeChannel) {
                ForEach(CurveChannel.allCases, id: \.self) { ch in
                    Text(ch.rawValue).tag(ch)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HistogramView(histogram: histogram)
                .frame(height: 60)

            CurveEditorView(curve: activeCurveBinding, color: activeChannel.color)
                .frame(height: 150)

            paletteResetButton("Reset Curves") { settings.curves = Curves() }
        }
        .padding(10)
    }

    private var activeCurveBinding: Binding<ToneCurve> {
        switch activeChannel {
        case .composite: return $settings.curves.composite
        case .red:       return $settings.curves.red
        case .green:     return $settings.curves.green
        case .blue:      return $settings.curves.blue
        }
    }
}

struct ColorBalanceContent: View {
    @EnvironmentObject var settings: ScanSettings

    var body: some View {
        VStack(spacing: 6) {
            NikonSlider(label: "Red",
                        value: Binding(get: { settings.colorBalance.x },
                                       set: { settings.colorBalance.x = $0 }),
                        range: -100...100)
            NikonSlider(label: "Green",
                        value: Binding(get: { settings.colorBalance.y },
                                       set: { settings.colorBalance.y = $0 }),
                        range: -100...100)
            NikonSlider(label: "Blue",
                        value: Binding(get: { settings.colorBalance.z },
                                       set: { settings.colorBalance.z = $0 }),
                        range: -100...100)
            NikonSlider(label: "Saturation", value: $settings.saturation, range: -100...100)

            paletteResetButton("Reset Color") {
                settings.colorBalance = .zero
                settings.saturation = 0
            }
        }
        .padding(10)
    }
}

struct DigitalICEContent: View {
    @EnvironmentObject var settings: ScanSettings
    @EnvironmentObject var scanner: ScannerManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NikonRow("Digital ICE") {
                Picker("", selection: $settings.digitalICE) {
                    ForEach(DigitalICE.allCases) { ice in
                        Text(ice.rawValue).tag(ice)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .disabled(!(scanner.connectedScanner?.model.supportsDigitalICE ?? true))
            }
            paletteNote(settings.digitalICE == .off
                        ? "Infrared dust removal is off."
                        : "Uses the SANE infrared channel when the holder/mode allows it.")
        }
        .padding(10)
    }
}

struct AnalogGainContent: View {
    @EnvironmentObject var settings: ScanSettings

    var body: some View {
        VStack(spacing: 6) {
            NikonSlider(label: "Exposure (EV)", value: $settings.brightness, range: -3...3)
            NikonSlider(label: "Contrast", value: $settings.contrast, range: -3...3)
            NikonSlider(label: "Gamma", value: $settings.gamma, range: 0.2...3.0)

            paletteResetButton("Reset Gain") {
                settings.brightness = 0
                settings.contrast   = 0
                settings.gamma      = 1
            }
        }
        .padding(10)
    }
}

struct FilmPresetContent: View {
    @EnvironmentObject var settings: ScanSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NikonRow("Film") {
                Picker("", selection: Binding(
                    get: { settings.activePreset },
                    set: { $0.apply(to: settings) }
                )) {
                    ForEach(FilmPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            paletteNote("Applies tone/color starting points. Fine-tune with Curves and Color Balance.")
        }
        .padding(10)
    }
}

struct ScannerExtrasContent: View {
    @EnvironmentObject var settings: ScanSettings
    @EnvironmentObject var scanner: ScannerManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NikonRow("Resolution") {
                Picker("", selection: $settings.resolution) {
                    let resolutions = scanner.connectedScanner?.model.availableResolutions ?? [300, 600, 1200, 2400, 4000]
                    ForEach(resolutions, id: \.self) { r in
                        Text("\(r) dpi").tag(r)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            NikonRow("Bit Depth") {
                Picker("", selection: $settings.bitDepth) {
                    ForEach(BitDepth.allCases) { bd in
                        Text(bd.rawValue).tag(bd)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            NikonRow("Save As") {
                Picker("", selection: $settings.outputFormat) {
                    ForEach(OutputFormat.allCases) { fmt in
                        Text(fmt.rawValue).tag(fmt)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            NikonToggleRow("Auto Focus", isOn: $settings.autoFocus)
            NikonToggleRow("Multi-Sample", isOn: $settings.multiScan)
            if settings.multiScan {
                NikonRow("Passes") {
                    Picker("", selection: $settings.multiScanCount) {
                        Text("4×").tag(4)
                        Text("8×").tag(8)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            }

            Divider()

            NikonToggleRow("Auto-Align Frame", isOn: $settings.autoAlign)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Right Crop")
                    Spacer()
                    Text("\(settings.alignmentOffset) px").monospacedDigit()
                }
                .font(.lucida(10.5))
                .foregroundColor(.aquaTextDim)
                Slider(
                    value: Binding(
                        get: { Double(settings.alignmentOffset) },
                        set: { settings.alignmentOffset = Int($0.rounded()) }
                    ),
                    in: -100...400,
                    step: 1
                )
                .controlSize(.small)
            }

            NikonRow("Rotate") {
                HStack(spacing: 6) {
                    Button { settings.rotation = (settings.rotation + 270) % 360 } label: {
                        Image(systemName: "rotate.left")
                    }
                    Button { settings.rotation = (settings.rotation + 90) % 360 } label: {
                        Image(systemName: "rotate.right")
                    }
                    Text("\(settings.rotation)°")
                        .font(.lucida(10.5))
                        .foregroundColor(.aquaTextDim)
                }
                .controlSize(.small)
            }

            if settings.bitDepth != .bit8 {
                paletteNote("Requests 16-bit from SANE; falls back to 8-bit on firmware errors.")
            }

            paletteResetButton("Reset All Adjustments") { settings.reset() }
        }
        .padding(10)
    }
}

struct UnavailableContent: View {
    let text: String
    var body: some View {
        paletteNote(text).padding(10)
    }
}

// MARK: - Reusable components (light Aqua styling)

struct NikonRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(label)
                .font(.lucida(11))
                .foregroundColor(.aquaTextDim)
                .frame(width: 72, alignment: .trailing)
            content
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct NikonToggleRow: View {
    let label: String
    @Binding var isOn: Bool

    init(_ label: String, isOn: Binding<Bool>) {
        self.label = label
        self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(label)
                .font(.lucida(11))
                .foregroundColor(.aquaText)
        }
        .toggleStyle(.checkbox)
        .controlSize(.small)
    }
}

struct NikonSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(label)
                    .foregroundColor(.aquaTextDim)
                Spacer()
                Text(String(format: valueFormat, value))
                    .monospacedDigit()
                    .foregroundColor(.aquaText)
            }
            .font(.lucida(10.5))
            Slider(value: $value, in: range)
                .controlSize(.small)
        }
    }

    private var valueFormat: String {
        range.upperBound > 10 ? "%.0f" : "%.2f"
    }
}

private func paletteNote(_ text: String) -> some View {
    Text(text)
        .font(.lucida(10))
        .foregroundColor(.aquaTextDim)
        .fixedSize(horizontal: false, vertical: true)
}

private func paletteResetButton(_ label: String, action: @escaping () -> Void) -> some View {
    HStack {
        Spacer()
        Button(label, action: action)
            .controlSize(.small)
            .font(.lucida(11))
    }
}
