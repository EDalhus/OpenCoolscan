import SwiftUI
import AppKit

// MARK: - Tool Palette window (right side, disclosure rows like Nikon Scan 4)

struct ToolPaletteWindow: View {
    let histogram: HistogramData
    var onClose: () -> Void

    enum Section: String, CaseIterable, Identifiable {
        case curves         = "Curves"
        case colorBalance   = "Color Balance"
        case unsharpMask    = "Unsharp Mask"
        case digitalICE     = "Digital ICE⁴ Advanced"
        case analogGain     = "Analog Gain"
        case enhancer       = "Scan Image Enhancer"
        case scannerExtras  = "Scanner Extras"
        var id: String { rawValue }
    }

    @State private var expanded: Set<Section> = []

    var body: some View {
        AquaWindow {
            VStack(spacing: 0) {
                AquaTitleBar(
                    title: "Tool Palette 1",
                    height: 16,
                    fontSize: 12,
                    onClose: onClose,
                    onMinimize: { expanded = [] },
                    onZoom: { expanded = expanded.count == Section.allCases.count ? [] : Set(Section.allCases) }
                )

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(Section.allCases) { section in
                            PaletteRow(title: section.rawValue, isExpanded: binding(for: section))
                            if expanded.contains(section) {
                                content(for: section)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background { Color(hex: 0xDEDEDE) }
                                    .overlay(alignment: .bottom) { Color(hex: 0x9A9A9A).frame(height: 1) }
                            }
                        }
                    }
                    .padding(.top, 3)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func binding(for section: Section) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(section) },
            set: { if $0 { expanded.insert(section) } else { expanded.remove(section) } }
        )
    }

    @ViewBuilder
    private func content(for section: Section) -> some View {
        switch section {
        case .curves:        CurvesContent(histogram: histogram)
        case .colorBalance:  ColorBalanceContent()
        case .unsharpMask:   UnavailableContent(text: "Unsharp Mask is not implemented yet.")
        case .digitalICE:    DigitalICEContent()
        case .analogGain:    AnalogGainContent()
        case .enhancer:      FilmPresetContent()
        case .scannerExtras: ScannerExtrasContent()
        }
    }
}

struct PaletteRow: View {
    let title: String
    @Binding var isExpanded: Bool

    var body: some View {
        Button { isExpanded.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "arrowtriangle.down.fill" : "arrowtriangle.right.fill")
                    .font(.system(size: 7))
                    .foregroundColor(Color(hex: 0x2A2A2A))
                    .frame(width: 10)
                Text(title)
                    .font(.lucida(12.5, bold: true))
                    .foregroundColor(.aquaText)
                Spacer()
            }
            .padding(.leading, 7)
            .frame(height: 23)
            .background(LinearGradient(colors: [Color(hex: 0xF0F0F0), Color(hex: 0xE4E4E4)],
                                       startPoint: .top, endPoint: .bottom))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) {
                Color(hex: 0x7A7A7A).frame(height: 1.2)
                Color.white.frame(height: 1)
            }
        }
        .padding(.bottom, 1)
    }
}
