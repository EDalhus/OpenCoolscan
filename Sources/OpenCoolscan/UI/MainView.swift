import SwiftUI
import AppKit
import Combine

// MARK: - Layout (points, measured from the Nikon Scan 4 design reference)

enum DesignLayout {
    static let defaultSize      = CGSize(width: 1290, height: 792)

    static let scannerWindow    = CGRect(x: 0, y: 0, width: 805, height: 285)
    static var scannerWindowSize: CGSize { CGSize(width: scannerWindow.width, height: drawer.maxY + 2) }
    static let imageMinSize     = CGSize(width: 360, height: 280)
    static let titleHeight: CGFloat = 22
    static let leftColumnWidth: CGFloat = 152
    static let drawer           = CGRect(x: 0, y: 168, width: 176, height: 358)

    static let imageLeft: CGFloat        = 380
    static let imageTop: CGFloat         = 311
    static let imageGapToPalette: CGFloat = 88
    static let imageBottomGap: CGFloat   = 116

    static let progressSize     = CGSize(width: 342, height: 237)
    static let progressInset    = CGPoint(x: 13, y: 19)   // from left / bottom

    static let paletteWidth: CGFloat     = 263
    static let paletteRightGap: CGFloat  = 13
    static let paletteTop: CGFloat       = 8
}

struct PixelRGB: Equatable { let r, g, b: Int }

// MARK: - Window roots

/// Scanner window with the left drawer attached below its tool column.
struct ScannerWindowRoot: View {
    @EnvironmentObject var scanner: ScannerManager
    @EnvironmentObject var settings: ScanSettings
    @EnvironmentObject var workspace: Workspace
    @EnvironmentObject var windows: WindowManager

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScannerWindow(
                onEject:      { scanner.eject() },
                onPreviewAll: { Task { await scanner.autoPreviewAllFrames(settings: settings) } },
                onZoomIn:     { workspace.zoomIn() },
                onZoomOut:    { workspace.zoomOut() }
            )
            .frame(width: DesignLayout.scannerWindow.width, height: DesignLayout.scannerWindow.height)

            LeftDrawer(
                image: workspace.viewImage,
                hoverRGB: workspace.hoverRGB,
                histogram: workspace.histogram,
                onPreview: { workspace.preview() },
                onScan: { workspace.scan() },
                onPrefs: { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) },
                onHelp:  { NSApp.orderFrontStandardAboutPanel(nil) },
                onTools: { windows.showPalette.toggle() }
            )
            .frame(width: DesignLayout.drawer.width, height: DesignLayout.drawer.height)
            .offset(y: DesignLayout.drawer.minY)
        }
        .frame(width: DesignLayout.scannerWindowSize.width, height: DesignLayout.scannerWindowSize.height,
               alignment: .topLeading)
    }
}

struct ImageWindowRoot: View {
    @EnvironmentObject var scanner: ScannerManager
    @EnvironmentObject var settings: ScanSettings
    @EnvironmentObject var workspace: Workspace

    var body: some View {
        ImageWindow(
            image: workspace.viewImage,
            frameNumber: scanner.selectedFrame + 1,
            orientation: settings.orientation(for: scanner.selectedFrame),
            settings: settings,
            zoom: $workspace.zoom,
            hoverRGB: $workspace.hoverRGB
        )
        .padding(.bottom, 1)
    }
}

struct ToolPaletteRoot: View {
    @EnvironmentObject var workspace: Workspace
    var onClose: () -> Void

    var body: some View {
        ToolPaletteWindow(histogram: workspace.histogram, onClose: onClose)
            .overlay(alignment: .bottom) {
                PanelResizeHandle(mode: .height)
                    .frame(height: 6)
                    .onHover { inside in
                        if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                    }
            }
    }
}

func scannerTitle(_ device: ScannerDevice?) -> String {
    guard let device else { return "No Scanner — click to select" }
    let name: String
    switch device.model {
    case .ls4000:    name = "SUPER COOLSCAN 4000 ED"
    case .ls5000:    name = "SUPER COOLSCAN 5000 ED"
    case .ls8000:    name = "SUPER COOLSCAN 8000 ED"
    case .ls9000:    name = "SUPER COOLSCAN 9000 ED"
    case .ls40:      name = "COOLSCAN IV ED"
    case .ls50:      name = "COOLSCAN V ED"
    case .ls2000:    name = "SUPER COOLSCAN LS-2000"
    case .ls30:      name = "COOLSCAN III"
    case .simulated: return "Nikon Simulated Scanner"
    }
    return "Nikon \(name) @ USB"
}

// MARK: - Scanner Window (title bar, tool column, thumbnail area)

struct ScannerWindow: View {
    @EnvironmentObject var scanner: ScannerManager
    @EnvironmentObject var settings: ScanSettings
    @EnvironmentObject var windows: WindowManager
    var onEject: () -> Void
    var onPreviewAll: () -> Void
    var onZoomIn: () -> Void
    var onZoomOut: () -> Void

    private var noScanner: Bool { scanner.connectedScanner == nil }

    var body: some View {
        AquaWindow {
            VStack(spacing: 0) {
                AquaTitleBar(
                    title: scannerTitle(scanner.connectedScanner),
                    height: DesignLayout.titleHeight,
                    onClose:    { windows.closeScannerWindow() },
                    onMinimize: { windows.toggleCollapsed(.scanner) },
                    onZoom:     { windows.showAll() },
                    onTitleClick: showScannerMenu
                )
                .help("Click to choose scanner")

                HStack(spacing: 0) {
                    toolColumn
                        .frame(width: DesignLayout.leftColumnWidth)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .background { Color.aquaSidePanel }
                        .overlay(alignment: .trailing) {
                            HStack(spacing: 0) {
                                Color(hex: 0x6E6E6E).frame(width: 1)
                                Color(hex: 0xB0B0B0).frame(width: 2)
                            }
                        }
                    FrameGridArea()
                }
            }
        }
    }

    private var toolColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                AquaBevelButton(systemImage: "eject.fill", disabled: noScanner || scanner.isBusy,
                                help: "Eject film", action: onEject)
                AquaBevelButton(systemImage: "square.grid.3x3.fill",
                                pressed: scanner.isAutoPreviewingAll,
                                disabled: noScanner || scanner.isBusy,
                                help: "Preview all frames (thumbnails)", action: onPreviewAll)
                AquaBevelButton(systemImage: "circle.lefthalf.filled",
                                pressed: settings.showOriginal,
                                help: "Toggle Processed / Natural") { settings.showOriginal.toggle() }
            }
            .padding(.top, 6.5)

            HStack(spacing: 10) {
                AquaBevelButton(systemImage: "minus.magnifyingglass", help: "Zoom out", action: onZoomOut)
                AquaBevelButton(systemImage: "plus.magnifyingglass", help: "Zoom in", action: onZoomIn)
            }
            .padding(.top, 3)

            VStack(spacing: 7) {
                AquaPopup(label: settings.activePreset == .none ? "Last Used" : settings.activePreset.rawValue) {
                    FilmPreset.allCases.map { preset in
                        PopupMenu.Item(title: preset == .none ? "Last Used" : preset.rawValue,
                                       checked: settings.activePreset == preset) { preset.apply(to: settings) }
                    }
                }
                AquaPopup(label: settings.filmType.shortName) {
                    FilmType.allCases.map { ft in
                        PopupMenu.Item(title: ft.shortName, checked: settings.filmType == ft) { settings.filmType = ft }
                    }
                }
                AquaPopup(label: settings.colorSpace == .gray ? "Grayscale" : "Calibrated RGB") {
                    [
                        PopupMenu.Item(title: "Calibrated RGB", checked: settings.colorSpace != .gray) {
                            let raw = UserDefaults.standard.string(forKey: "workingColorSpace") ?? ""
                            let space = ColorSpace(rawValue: raw) ?? .sRGB
                            settings.colorSpace = space == .gray ? .sRGB : space
                        },
                        PopupMenu.Item(title: "Grayscale", checked: settings.colorSpace == .gray) {
                            settings.colorSpace = .gray
                        }
                    ]
                }
            }
            .padding(.horizontal, 7)
            .padding(.top, 5)
        }
    }

    private func showScannerMenu() {
        var items = scanner.availableScanners.map { dev in
            PopupMenu.Item(title: dev.name, checked: dev == scanner.connectedScanner,
                           enabled: !scanner.isBusy) { scanner.connect(to: dev) }
        }
        if items.isEmpty {
            items = [PopupMenu.Item(title: "No scanners found", enabled: false) {}]
        }
        PopupMenu.show(items)
    }
}

// MARK: - Thumbnail area

struct FrameGridArea: View {
    @EnvironmentObject var scanner: ScannerManager
    @EnvironmentObject var settings: ScanSettings

    private let pitch = CGSize(width: 148.4, height: 102)
    private let origin = CGPoint(x: 40.6, y: 34.8)
    private let columns = 4

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.aquaFrameArea

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: pitch.height - FrameThumb.size.height) {
                    ForEach(rows, id: \.self) { row in
                        HStack(spacing: pitch.width - FrameThumb.size.width) {
                            ForEach(row, id: \.self) { i in
                                FrameThumb(
                                    index: i,
                                    image: scanner.framePreviews[i],
                                    state: scanner.jobState(for: i),
                                    orientation: settings.orientation(for: i),
                                    isPrimary: scanner.selectedFrame == i,
                                    inSelection: scanner.selectedFrames.contains(i)
                                ) { cmd, shift in
                                    scanner.selectFrame(i, cmd: cmd, shift: shift)
                                }
                            }
                        }
                    }
                }
                .padding(.leading, origin.x)
                .padding(.top, origin.y)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Select-all toggle (top-left)
            Button {
                let all = Set(0..<max(scanner.totalFrames, 1))
                if scanner.selectedFrames == all {
                    scanner.selectFrame(scanner.selectedFrame)
                } else {
                    scanner.selectedFrames = all
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(LinearGradient(colors: [Color(hex: 0xF4F4F4), Color(hex: 0xCFCFCF)],
                                             startPoint: .top, endPoint: .bottom))
                    RoundedRectangle(cornerRadius: 2).stroke(Color(hex: 0x555555), lineWidth: 1)
                    Rectangle().fill(Color.black).frame(width: 11, height: 11)
                    Rectangle().stroke(Color.white, lineWidth: 1).frame(width: 9, height: 9)
                }
                .frame(width: 19, height: 19)
            }
            .buttonStyle(.plain)
            .help("Select all frames")
            .offset(x: 11, y: 8.4)

            VStack {
                cornerArrow(systemImage: "arrowtriangle.left.fill", help: "Previous frame") {
                    scanner.selectFrame(max(0, scanner.selectedFrame - 1))
                }
                Spacer()
                cornerArrow(systemImage: "arrowtriangle.down.fill", rotation: -45, help: "Next frame") {
                    scanner.selectFrame(min(scanner.totalFrames - 1, scanner.selectedFrame + 1))
                }
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .padding(.trailing, 4)
        }
        .overlay(alignment: .top) { Color.black.opacity(0.25).frame(height: 1) }
    }

    private var rows: [[Int]] {
        let count = max(scanner.totalFrames, 1)
        return stride(from: 0, to: count, by: columns).map { start in
            Array(start..<min(start + columns, count))
        }
    }

    private func cornerArrow(systemImage: String, rotation: Double = 0, help: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Rectangle().fill(Color(hex: 0xA8A8A8))
                Rectangle().stroke(Color(hex: 0x5E5E5E), lineWidth: 1)
                Image(systemName: systemImage)
                    .font(.system(size: 8))
                    .foregroundColor(.aquaTeal)
                    .rotationEffect(.degrees(rotation))
            }
            .frame(width: 15, height: 15)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct FrameThumb: View {
    static let size = CGSize(width: 111.6, height: 74.8)

    let index: Int
    let image: NSImage?
    let state: ScannerManager.FrameJobState
    var orientation = FrameOrientation()
    let isPrimary: Bool
    let inSelection: Bool
    let onTap: (_ cmd: Bool, _ shift: Bool) -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color(hex: 0x0D0D0D))

                Group {
                    if let image {
                        let inner = CGSize(width: Self.size.width - 9, height: Self.size.height - 8)
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: orientation.swapsAxes ? .fit : .fill)
                            .frame(width: orientation.swapsAxes ? inner.height : inner.width,
                                   height: orientation.swapsAxes ? inner.width : inner.height)
                            .scaleEffect(x: orientation.flipHorizontal ? -1 : 1, y: orientation.flipVertical ? -1 : 1)
                            .rotationEffect(.degrees(Double(orientation.rotation)))
                    } else {
                        LinearGradient(colors: [Color(hex: 0x2A2A2A), Color(hex: 0x1A1A1A)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                }
                .frame(width: Self.size.width - 9, height: Self.size.height - 8)
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    if case .active(let p) = state {
                        Color.aquaTeal
                            .frame(width: (Self.size.width - 9) * max(0.02, p), height: 2.5)
                    }
                }
                .overlay(alignment: .topLeading) { badge.padding(3) }
                .offset(x: 4.5, y: 4)
            }
            .frame(width: Self.size.width, height: Self.size.height)
            .overlay {
                if inSelection && !isPrimary {
                    Rectangle().stroke(Color(hex: 0x5DC4B8), lineWidth: 1.2)
                }
            }
            .overlay {
                if isPrimary { CornerBrackets().padding(-3.5) }
            }

            Text("\(index + 1)")
                .font(.lucida(11))
                .foregroundColor(.aquaTealLabel)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            let mods = NSEvent.modifierFlags
            onTap(mods.contains(.command), mods.contains(.shift))
        }
    }

    @ViewBuilder
    private var badge: some View {
        switch state {
        case .done:
            badgeLabel("✓ Done", background: .aquaBadgeDone)
        case .active(let p):
            badgeLabel("\(Int((p * 100).rounded()))%", background: .aquaBadgeActive)
        case .waiting:
            badgeLabel("Waiting", background: .aquaBadgeWaiting)
        case .idle:
            EmptyView()
        }
    }

    private func badgeLabel(_ text: String, background: Color) -> some View {
        Text(text)
            .font(.lucida(9.5))
            .foregroundColor(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background { background }
    }
}

/// Teal corner brackets around the current frame.
struct CornerBrackets: View {
    var length: CGFloat = 10
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height, l = length
            var p = Path()
            p.move(to: CGPoint(x: 0, y: l));       p.addLine(to: .zero);                       p.addLine(to: CGPoint(x: l, y: 0))
            p.move(to: CGPoint(x: w - l, y: 0));   p.addLine(to: CGPoint(x: w, y: 0));         p.addLine(to: CGPoint(x: w, y: l))
            p.move(to: CGPoint(x: w, y: h - l));   p.addLine(to: CGPoint(x: w, y: h));         p.addLine(to: CGPoint(x: w - l, y: h))
            p.move(to: CGPoint(x: l, y: h));       p.addLine(to: CGPoint(x: 0, y: h));         p.addLine(to: CGPoint(x: 0, y: h - l))
            ctx.stroke(p, with: .color(.aquaTeal), lineWidth: 2.5)
        }
    }
}

// MARK: - Left drawer (Prefs / Help / Tools, info, RGB, Preview / Scan)

struct LeftDrawer: View {
    @EnvironmentObject var scanner: ScannerManager
    @EnvironmentObject var settings: ScanSettings
    let image: NSImage?
    let hoverRGB: PixelRGB?
    let histogram: HistogramData
    var onPreview: () -> Void
    var onScan: () -> Void
    var onPrefs: () -> Void
    var onHelp: () -> Void
    var onTools: () -> Void

    @State private var showHistogram = false

    private var disabled: Bool { scanner.connectedScanner == nil || scanner.isBusy }

    var body: some View {
        ZStack(alignment: .topLeading) {
            DrawerShape()
                .fill(Color.aquaSidePanel)
                .overlay(DrawerShape().stroke(Color(hex: 0x6E6E6E), lineWidth: 1))

            DragHandle().padding(.top, 10).padding(.trailing, 10)

            orb("Prefs", color: Color(hex: 0x8CC4F2), dark: Color(hex: 0x2A6CB8), center: CGPoint(x: 33.5, y: 59.4), action: onPrefs)
            orb("Help",  color: Color(hex: 0x9EE6CF), dark: Color(hex: 0x2F9A80), center: CGPoint(x: 87.1, y: 45.2), action: onHelp)
            orb("Tools", color: Color(hex: 0xCDA8F4), dark: Color(hex: 0x6A3CB0), center: CGPoint(x: 141.3, y: 59.4),
                badge: true, action: onTools)

            infoBox
                .frame(width: 160, height: 153.5)
                .offset(x: 7.7, y: 77.4)

            rgbBox
                .frame(width: 160, height: 29)
                .offset(x: 7.7, y: 237.4)

            bigOrb(label: "Preview", color: Color(hex: 0x9BEAE3), dark: Color(hex: 0x1F8F88),
                   centerX: 47.1, action: onPreview)
            bigOrb(label: scanner.selectedFrames.count > 1 ? "Scan \(scanner.selectedFrames.count)" : "Scan",
                   color: Color(hex: 0xA6F08E), dark: Color(hex: 0x2A9A1E),
                   centerX: 128.4, action: onScan)
        }
    }

    private func orb(_ label: String, color: Color, dark: Color, center: CGPoint,
                     badge: Bool = false, action: @escaping () -> Void) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.lucida(11.5))
                .foregroundColor(Color(hex: 0x1A1A1A))
            GlossyOrb(color: color, dark: dark, diameter: 23, ring: false, badge: badge, action: action)
        }
        .frame(width: 60)
        .position(x: center.x, y: center.y - 6)
    }

    private func bigOrb(label: String, color: Color, dark: Color, centerX: CGFloat,
                        action: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.lucida(12.5))
                .foregroundColor(disabled ? Color(hex: 0x555555) : Color(hex: 0x1A1A1A))
            GlossyOrb(color: color, dark: dark, diameter: 47, disabled: disabled, action: action)
        }
        .frame(width: 80)
        .position(x: centerX, y: 307)
    }

    private var infoBox: some View {
        ZStack(alignment: .topLeading) {
            Color.aquaInfo
            GridPattern(spacing: 8).stroke(Color.white.opacity(0.05), lineWidth: 1)

            if showHistogram {
                HistogramView(histogram: histogram)
                    .padding(.top, 30)
                    .padding([.horizontal, .bottom], 6)
            } else {
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(infoRows, id: \.0) { row in
                        Text("\(row.0): \(row.1)")
                            .font(.lucida(10.5))
                            .foregroundColor(Color(hex: 0xEDEDED))
                            .lineLimit(1)
                            .frame(height: 12.6)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 7)
                .padding(.top, 7)
            }

            Button { showHistogram.toggle() } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 1.5).fill(Color(hex: 0x8C1E18))
                    RoundedRectangle(cornerRadius: 1.5).stroke(Color(hex: 0x3A0A08), lineWidth: 1)
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(2)
                        .overlay(Rectangle().stroke(Color.white, lineWidth: 1).padding(1))
                }
                .frame(width: 22, height: 19)
            }
            .buttonStyle(.plain)
            .help(showHistogram ? "Show image info" : "Show histogram")
            .offset(x: 5, y: 7.7)
        }
        .overlay(Rectangle().stroke(Color.aquaInfoBorder, lineWidth: 2))
    }

    private var infoRows: [(String, String)] {
        let size = pixelSize(of: image)
        let bits = settings.bitDepth == .bit8 ? 8 : 14
        let bytesPerPixel = (settings.isGrayscale ? 1 : 3) * (bits > 8 ? 2 : 1)
        let fileSize = size.map { String(format: "%.1f MB", Double($0.width * $0.height * bytesPerPixel) / 1_048_576) } ?? "—"
        return [
            ("W", size.map { "\($0.width) px" } ?? "—"),
            ("H", size.map { "\($0.height) px" } ?? "—"),
            ("File size", fileSize),
            ("Analog Gain", settings.brightness == 0 ? "Neutral" : String(format: "%+.2f EV", settings.brightness)),
            ("Digital ROC", "Off"),
            ("Digital GEM", "Off"),
            ("Digital ICE", settings.digitalICE == .off ? "Off" : settings.digitalICE.rawValue),
            ("Digital DEE", "Off"),
            ("SIEnhancer", settings.activePreset == .none ? "Neutral" : settings.activePreset.rawValue),
            ("Multi Sample", settings.multiScan ? "\(settings.multiScanCount)x" : "1x"),
            ("Bit depth", "\(bits) bits")
        ]
    }

    private var rgbBox: some View {
        HStack(spacing: 0) {
            Text("R \(hoverRGB.map { String($0.r) } ?? "–")").frame(width: 48, alignment: .leading)
            Text("G \(hoverRGB.map { String($0.g) } ?? "–")").frame(width: 55, alignment: .leading)
            Text("B \(hoverRGB.map { String($0.b) } ?? "–")")
            Spacer(minLength: 0)
        }
        .font(.lucida(10.5))
        .foregroundColor(Color(hex: 0xEDEDED))
        .padding(.leading, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { Color(hex: 0x5A5A5A) }
        .overlay(Rectangle().stroke(Color(hex: 0x2A2A2A), lineWidth: 2))
    }
}

func pixelSize(of image: NSImage?) -> (width: Int, height: Int)? {
    guard let image else { return nil }
    if let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
        return (rep.pixelsWide, rep.pixelsHigh)
    }
    return (Int(image.size.width), Int(image.size.height))
}

/// Drawer outline: square top-left (joins the tool column), rounded right corners.
struct DrawerShape: Shape {
    func path(in r: CGRect) -> Path {
        let rad: CGFloat = 9
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - rad, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + rad), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - rad))
        p.addQuadCurve(to: CGPoint(x: r.maxX - rad, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct GridPattern: Shape {
    let spacing: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        var x = r.minX
        while x <= r.maxX { p.move(to: CGPoint(x: x, y: r.minY)); p.addLine(to: CGPoint(x: x, y: r.maxY)); x += spacing }
        var y = r.minY
        while y <= r.maxY { p.move(to: CGPoint(x: r.minX, y: y)); p.addLine(to: CGPoint(x: r.maxX, y: y)); y += spacing }
        return p
    }
}
