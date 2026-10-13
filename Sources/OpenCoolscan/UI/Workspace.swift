import SwiftUI
import AppKit
import Combine
import CoolscanKit

// MARK: - Shared app objects

@MainActor
final class AppModel {
    static let shared = AppModel()

    let scanner = ScannerManager()
    let settings = ScanSettings()
    lazy var workspace = Workspace(scanner: scanner, settings: settings)
    lazy var windows = WindowManager(model: self)
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.shared.settings.applyDefaultsFromPreferences()
        AppModel.shared.windows.showAll()
        // Don't let window restoration reopen Preferences on launch.
        DispatchQueue.main.async {
            for window in NSApp.windows where window !== AppModel.shared.windows.mainWindow && window.isVisible {
                window.close()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppModel.shared.windows.showAll()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

// MARK: - Workspace (state shared between the floating windows)

@MainActor
final class Workspace: ObservableObject {
    let scanner: ScannerManager
    let settings: ScanSettings

    @Published private(set) var viewImage: NSImage?
    @Published private(set) var histogram = HistogramData.empty
    @Published var zoom: CGFloat?          // nil = fit to window
    @Published var hoverRGB: PixelRGB?

    private var rawFrameImage: NSImage?
    private var bag = Set<AnyCancellable>()

    init(scanner: ScannerManager, settings: ScanSettings) {
        self.scanner = scanner
        self.settings = settings

        scanner.$selectedFrame
            .sink { [weak self] frame in
                guard let self else { return }
                if let raw = scanner.framePreviews[frame] {
                    self.setRawImage(raw, frame: frame)
                } else {
                    self.rawFrameImage = nil
                    self.viewImage = nil
                    scanner.displayedImage = nil
                }
            }
            .store(in: &bag)

        scanner.$framePreviews
            .sink { [weak self] previews in
                guard let self else { return }
                if let raw = previews[scanner.selectedFrame] {
                    self.setRawImage(raw, frame: scanner.selectedFrame)
                }
            }
            .store(in: &bag)

        settings.objectWillChange
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.redraw() }
            .store(in: &bag)

        NotificationCenter.default.publisher(for: .nikonRedrawRequested)
            .sink { [weak self] _ in self?.redraw() }
            .store(in: &bag)

        scanner.$lastError
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] message in
                let alert = NSAlert()
                alert.messageText = "Scanner Error"
                alert.informativeText = message
                alert.alertStyle = .warning
                alert.runModal()
                self?.scanner.lastError = nil
            }
            .store(in: &bag)
    }

    func redraw() {
        guard let raw = rawFrameImage else { return }
        refreshDisplay(from: raw, frame: scanner.selectedFrame)
    }

    private func setRawImage(_ raw: NSImage, frame: Int) {
        rawFrameImage = raw
        refreshDisplay(from: raw, frame: frame)
    }

    private func refreshDisplay(from raw: NSImage, frame: Int) {
        // The view shows the full frame; the crop is drawn as a marquee on top.
        if settings.showOriginal {
            viewImage = ImageProcessor.orient(raw, settings.orientation(for: frame))
        } else {
            viewImage = ImageProcessor.apply(settings: settings, to: raw, includeCrop: false, frame: frame)
        }
        scanner.displayedImage = viewImage
        if let img = viewImage { histogram = HistogramData.compute(from: img) }
    }

    // MARK: Actions

    func preview() { Task { await scanner.preview(settings: settings) } }

    func scan() {
        Task {
            await scanner.scan(settings: settings)
            // Hardware already applied crop — reset so ImageProcessor won't double-crop.
            settings.cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        }
    }

    func zoomIn()  { zoom = min(8, (zoom ?? 1) * 1.5) }
    func zoomOut() {
        let next = (zoom ?? 1) / 1.5
        zoom = next <= 1.01 ? nil : next
    }

    func rotate(by degrees: Int) {
        settings.updateOrientation(frame: scanner.selectedFrame) { $0.rotate(by: degrees) }
    }

    func saveCurrentImage() {
        guard let raw = rawFrameImage else { return }
        let image = ImageProcessor.apply(settings: settings, to: raw, frame: scanner.selectedFrame)
        do {
            let url = try scanner.saveImage(image, settings: settings)
            scanner.statusMessage = "Saved: \(url.lastPathComponent)"
        } catch ScannerError.saveCancelled {
            // user dismissed
        } catch {
            scanner.lastError = error.localizedDescription
        }
    }

    func saveBatch() {
        do {
            _ = try scanner.saveBatch(settings: settings) { frame, raw in
                ImageProcessor.apply(settings: settings, to: raw, frame: frame)
            }
        } catch ScannerError.saveCancelled {
            // dismissed
        } catch {
            scanner.lastError = error.localizedDescription
        }
    }
}

// MARK: - Panels living inside the main app window

enum PanelID: String, CaseIterable {
    case image, progress, scanner, palette
}

private struct PanelIDKey: EnvironmentKey {
    static let defaultValue: PanelID? = nil
}

extension EnvironmentValues {
    /// The panel a view belongs to; nil for the main window's own chrome.
    var panelID: PanelID? {
        get { self[PanelIDKey.self] }
        set { self[PanelIDKey.self] = newValue }
    }
}

/// Positions, sizes, stacking order and visibility of the floating panels.
/// Panels the user has not moved follow the design layout as the window resizes.
@MainActor
final class WindowManager: ObservableObject {
    private unowned let model: AppModel
    private(set) var mainWindow: NSWindow?

    @Published private var positions: [PanelID: CGPoint] = [:]
    @Published private var imageSizeOverride: CGSize?
    @Published private var paletteHeightOverride: CGFloat?
    @Published private(set) var order: [PanelID] = [.image, .progress, .scanner, .palette]
    @Published private(set) var collapsed: Set<PanelID> = []
    @Published var containerSize: CGSize = DesignLayout.defaultSize

    @Published var showPalette: Bool {
        didSet { UserDefaults.standard.set(showPalette, forKey: "showToolPalette") }
    }
    @Published var showProgress: Bool {
        didSet { UserDefaults.standard.set(showProgress, forKey: "showProgressWindow") }
    }

    init(model: AppModel) {
        self.model = model
        showPalette = UserDefaults.standard.object(forKey: "showToolPalette") as? Bool ?? true
        showProgress = UserDefaults.standard.object(forKey: "showProgressWindow") as? Bool ?? true
        load()
    }

    // MARK: Main window

    func showAll() {
        if mainWindow == nil { createMainWindow() }
        showPalette = true
        showProgress = true
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeScannerWindow() { NSApp.terminate(nil) }
    func minimizeMainWindow() { mainWindow?.miniaturize(nil) }
    func zoomMainWindow() { mainWindow?.zoom(nil) }

    private func createMainWindow() {
        let vf = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let window = NSWindow(contentRect: vf,
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "OpenCoolscan"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(kind)?.isHidden = true
        }
        window.backgroundColor = NSColor(Color.aquaDesktop)
        window.minSize = NSSize(width: 960, height: 640)
        window.isReleasedWhenClosed = false

        let root = AppDesktopView()
            .environmentObject(model.scanner)
            .environmentObject(model.settings)
            .environmentObject(model.workspace)
            .environmentObject(self)
            .preferredColorScheme(.light)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        window.contentView = hosting

        if !window.setFrameUsingName("OpenCoolscan.main") {
            window.setFrame(vf, display: false)
        }
        window.setFrameAutosaveName("OpenCoolscan.main")
        mainWindow = window
    }

    // MARK: Geometry

    private var defaultImageSize: CGSize {
        let L = DesignLayout.self
        return CGSize(
            width: max(L.imageMinSize.width,
                       containerSize.width - L.imageLeft - L.imageGapToPalette - L.paletteWidth - L.paletteRightGap),
            height: max(L.imageMinSize.height, containerSize.height - L.imageTop - L.imageBottomGap))
    }

    func size(for id: PanelID) -> CGSize {
        let L = DesignLayout.self
        let full: CGSize
        switch id {
        case .scanner:  full = L.scannerWindowSize
        case .image:    full = imageSizeOverride ?? defaultImageSize
        case .progress: full = L.progressSize
        case .palette:  full = CGSize(width: L.paletteWidth,
                                      height: paletteHeightOverride ?? max(200, containerSize.height - L.paletteTop - 6))
        }
        return collapsed.contains(id) ? CGSize(width: full.width, height: titleHeight(id)) : full
    }

    func titleHeight(_ id: PanelID) -> CGFloat {
        switch id {
        case .scanner:  return DesignLayout.titleHeight
        case .image:    return 19
        case .progress: return 16
        case .palette:  return 20
        }
    }

    func position(for id: PanelID) -> CGPoint {
        clamp(positions[id] ?? defaultPosition(id), id)
    }

    private func defaultPosition(_ id: PanelID) -> CGPoint {
        let L = DesignLayout.self
        switch id {
        case .scanner:  return CGPoint(x: 3, y: 0)
        case .image:    return CGPoint(x: L.imageLeft, y: L.imageTop)
        case .progress: return CGPoint(x: L.progressInset.x,
                                       y: max(L.scannerWindowSize.height + 6,
                                              containerSize.height - L.progressInset.y - L.progressSize.height))
        case .palette:  return CGPoint(x: containerSize.width - L.paletteRightGap - L.paletteWidth, y: L.paletteTop)
        }
    }

    /// Keeps at least the title bar reachable inside the app window.
    private func clamp(_ p: CGPoint, _ id: PanelID) -> CGPoint {
        let w = size(for: id).width
        return CGPoint(x: min(max(p.x, 60 - w), containerSize.width - 60),
                       y: min(max(p.y, 0), containerSize.height - 20))
    }

    // MARK: Interaction

    func isVisible(_ id: PanelID) -> Bool {
        switch id {
        case .palette:  return showPalette
        case .progress: return showProgress
        default:        return true
        }
    }

    func bringToFront(_ id: PanelID) {
        guard order.last != id else { return }
        order.removeAll { $0 == id }
        order.append(id)
    }

    func move(_ id: PanelID, to p: CGPoint) {
        positions[id] = clamp(p, id)
    }

    func resizeImage(to size: CGSize) {
        imageSizeOverride = CGSize(width: max(DesignLayout.imageMinSize.width, size.width),
                                   height: max(DesignLayout.imageMinSize.height, size.height))
    }

    func resizePalette(height: CGFloat) {
        paletteHeightOverride = max(160, height)
    }

    func toggleCollapsed(_ id: PanelID) {
        guard id != .image else { return }
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
        save()
    }

    func resetLayout() {
        positions = [:]
        imageSizeOverride = nil
        paletteHeightOverride = nil
        collapsed = []
        save()
    }

    // MARK: Persistence

    private let defaultsKey = "OpenCoolscan.panelLayout"

    func save() {
        var dict: [String: [Double]] = [:]
        for (id, p) in positions { dict[id.rawValue] = [p.x, p.y] }
        if let s = imageSizeOverride { dict["imageSize"] = [s.width, s.height] }
        if let h = paletteHeightOverride { dict["paletteHeight"] = [h] }
        dict["collapsed"] = PanelID.allCases.map { collapsed.contains($0) ? 1 : 0 }
        UserDefaults.standard.set(dict, forKey: defaultsKey)
    }

    private func load() {
        guard let dict = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: [Double]] else { return }
        for id in PanelID.allCases {
            if let v = dict[id.rawValue], v.count == 2 { positions[id] = CGPoint(x: v[0], y: v[1]) }
        }
        if let v = dict["imageSize"], v.count == 2 { imageSizeOverride = CGSize(width: v[0], height: v[1]) }
        if let v = dict["paletteHeight"], v.count == 1 { paletteHeightOverride = v[0] }
        if let v = dict["collapsed"], v.count == PanelID.allCases.count {
            collapsed = Set(PanelID.allCases.enumerated().filter { v[$0.offset] == 1 }.map(\.element))
        }
    }
}

// MARK: - App window content

/// The main app window: full-width Aqua title bar over a gray work area that
/// hosts the floating panels.
struct AppDesktopView: View {
    @EnvironmentObject var windows: WindowManager
    @EnvironmentObject var settings: ScanSettings
    @EnvironmentObject var workspace: Workspace

    var body: some View {
        VStack(spacing: 0) {
            AquaTitleBar(
                title: "OpenCoolscan",
                height: DesignLayout.titleHeight,
                onClose:    { NSApp.terminate(nil) },
                onMinimize: { windows.minimizeMainWindow() },
                onZoom:     { windows.zoomMainWindow() }
            )

            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    Color.aquaDesktop

                    ForEach(PanelID.allCases, id: \.self) { id in
                        if windows.isVisible(id) {
                            let p = windows.position(for: id)
                            let size = windows.size(for: id)
                            panel(id)
                                .frame(width: size.width, height: size.height, alignment: .top)
                                .clipped()
                                .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 3)
                                .environment(\.panelID, id)
                                .simultaneousGesture(TapGesture().onEnded { windows.bringToFront(id) })
                                .offset(x: p.x, y: p.y)
                                .zIndex(Double(windows.order.firstIndex(of: id) ?? 0))
                        }
                    }
                }
                .coordinateSpace(name: "desktop")
                .clipped()
                .onAppear { windows.containerSize = geo.size }
                .onChange(of: geo.size) { windows.containerSize = $0 }
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func panel(_ id: PanelID) -> some View {
        switch id {
        case .scanner:  ScannerWindowRoot()
        case .image:    ImageWindowRoot()
        case .progress: ProgressWindow(onClose: { windows.showProgress = false })
        case .palette:  ToolPaletteRoot(onClose: { windows.showPalette = false })
        }
    }
}

/// Moves the panel it belongs to (or the app window, for the main title bar).
/// Double-click rolls a panel up into its title bar.
struct DragHandle: View {
    @Environment(\.panelID) private var panelID
    @EnvironmentObject private var windows: WindowManager
    @State private var start: CGPoint?

    var body: some View {
        if let id = panelID {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { windows.toggleCollapsed(id) }
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .named("desktop"))
                        .onChanged { g in
                            if start == nil {
                                start = windows.position(for: id)
                                windows.bringToFront(id)
                            }
                            guard let s = start else { return }
                            windows.move(id, to: CGPoint(x: s.x + g.translation.width, y: s.y + g.translation.height))
                        }
                        .onEnded { _ in
                            start = nil
                            windows.save()
                        }
                )
        } else {
            WindowDragArea()
        }
    }
}

/// Grow box / edge handle that resizes a panel, keeping its top-left fixed.
struct PanelResizeHandle: View {
    enum Mode { case both, height }
    var mode: Mode = .both
    @Environment(\.panelID) private var panelID
    @EnvironmentObject private var windows: WindowManager
    @State private var start: CGSize?

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("desktop"))
                    .onChanged { g in
                        guard let id = panelID else { return }
                        if start == nil { start = windows.size(for: id) }
                        guard let s = start else { return }
                        switch mode {
                        case .both:   windows.resizeImage(to: CGSize(width: s.width + g.translation.width,
                                                                     height: s.height + g.translation.height))
                        case .height: windows.resizePalette(height: s.height + g.translation.height)
                        }
                    }
                    .onEnded { _ in
                        start = nil
                        windows.save()
                    }
            )
    }
}
