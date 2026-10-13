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

    @AppStorage("toolPaletteExpanded") private var expandedRaw = ""

    private var expanded: Set<Section> {
        get { Set(expandedRaw.split(separator: "|").compactMap { Section(rawValue: String($0)) }) }
        nonmutating set { expandedRaw = Section.allCases.filter(newValue.contains).map(\.rawValue).joined(separator: "|") }
    }

    var body: some View {
        AquaWindow {
            VStack(spacing: 0) {
                AquaTitleBar(
                    title: "Tool Palette 1",
                    height: 20,
                    fontSize: 12.5,
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
                            }
                            PaletteSeparator()
                        }
                    }
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
        case .unsharpMask:   UnsharpMaskContent()
        case .digitalICE:    DigitalICEContent()
        case .analogGain:    AnalogGainContent()
        case .enhancer:      ScanImageEnhancerContent()
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
            .frame(height: 21)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Thick gray divider between palette sections.
struct PaletteSeparator: View {
    var body: some View {
        VStack(spacing: 0) {
            Color(hex: 0x8E8E8E).frame(height: 2.5)
            Color.white.frame(height: 1)
        }
    }
}
