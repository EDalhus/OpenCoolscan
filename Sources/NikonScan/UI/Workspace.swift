import SwiftUI
import AppKit
import Combine

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
            for window in NSApp.windows where !(window is ChromelessWindow || window is ChromelessPanel) && window.isVisible {
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

// MARK: - Floating windows

/// Borderless window that draws its own Aqua chrome but can still become key.
final class ChromelessWindow: NSWindow {
    init(size: CGSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .miniaturizable],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Floating utility panel (Tool Palette, Progress).
final class ChromelessPanel: NSPanel {
    init(size: CGSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isFloatingPanel = true
        hidesOnDeactivate = true
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
    }
    override var canBecomeKey: Bool { true }
}

@MainActor
final class WindowManager: ObservableObject {
    private unowned let model: AppModel
    private var scannerWindow: NSWindow?
    private var imageWindow: NSWindow?
    private var progressWindow: NSWindow?
    private var paletteWindow: NSWindow?

    @Published var showPalette: Bool {
        didSet { UserDefaults.standard.set(showPalette, forKey: "showToolPalette"); updateVisibility() }
    }
    @Published var showProgress: Bool {
        didSet { UserDefaults.standard.set(showProgress, forKey: "showProgressWindow"); updateVisibility() }
    }

    init(model: AppModel) {
        self.model = model
        showPalette = UserDefaults.standard.object(forKey: "showToolPalette") as? Bool ?? true
        showProgress = UserDefaults.standard.object(forKey: "showProgressWindow") as? Bool ?? true
    }

    func showAll() {
        if scannerWindow == nil { createWindows() }
        imageWindow?.orderFront(nil)
        scannerWindow?.makeKeyAndOrderFront(nil)
        updateVisibility()
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeScannerWindow() { NSApp.terminate(nil) }
    func minimizeScannerWindow() { scannerWindow?.miniaturize(nil) }

    private func updateVisibility() {
        guard scannerWindow != nil else { return }
        if showPalette { paletteWindow?.orderFront(nil) } else { paletteWindow?.orderOut(nil) }
        if showProgress { progressWindow?.orderFront(nil) } else { progressWindow?.orderOut(nil) }
    }

    private func host<V: View>(_ view: V, in window: NSWindow, title: String) {
        let root = view
            .environmentObject(model.scanner)
            .environmentObject(model.settings)
            .environmentObject(model.workspace)
            .environmentObject(self)
            .preferredColorScheme(.light)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        window.contentView = hosting
        window.title = title
        window.isExcludedFromWindowsMenu = false
        // The shadow follows the drawn (non-transparent) shapes once they have rendered.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { window.invalidateShadow() }
    }

    private func createWindows() {
        let vf = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let L = DesignLayout.self

        // Positions are given as top-left offsets within the visible screen area.
        func place(_ w: NSWindow, name: String, x: CGFloat, y: CGFloat, size: CGSize) {
            if !w.setFrameUsingName(name) {
                w.setFrame(NSRect(x: vf.minX + x, y: vf.maxY - y - size.height,
                                  width: size.width, height: size.height), display: false)
            }
            w.setFrameAutosaveName(name)
        }

        let scanner = ChromelessWindow(size: L.scannerWindowSize)
        host(ScannerWindowRoot(), in: scanner, title: "Nikon Scan")
        place(scanner, name: "NikonScan.scanner", x: 3, y: 0, size: L.scannerWindowSize)
        scannerWindow = scanner

        let imageSize = CGSize(
            width: max(L.imageMinSize.width, vf.width - L.imageLeft - L.imageGapToPalette - L.paletteWidth - L.paletteRightGap),
            height: max(L.imageMinSize.height, vf.height - L.imageTop - L.imageBottomGap))
        let image = ChromelessWindow(size: imageSize)
        host(ImageWindowRoot(), in: image, title: "Image")
        place(image, name: "NikonScan.image", x: L.imageLeft, y: L.imageTop, size: imageSize)
        imageWindow = image

        let progress = ChromelessPanel(size: L.progressSize)
        host(ProgressWindow(onClose: { [weak self] in self?.showProgress = false }), in: progress, title: "Progress")
        place(progress, name: "NikonScan.progress", x: L.progressInset.x,
              y: max(L.scannerWindowSize.height + 8, vf.height - L.progressInset.y - L.progressSize.height),
              size: L.progressSize)
        progressWindow = progress

        let paletteSize = CGSize(width: L.paletteWidth, height: vf.height - L.paletteTop - 4)
        let palette = ChromelessPanel(size: paletteSize)
        host(ToolPaletteRoot(onClose: { [weak self] in self?.showPalette = false }), in: palette, title: "Tool Palette 1")
        place(palette, name: "NikonScan.palette", x: vf.width - L.paletteRightGap - L.paletteWidth,
              y: L.paletteTop, size: paletteSize)
        paletteWindow = palette
    }
}

// MARK: - Window resizing (grow box)

/// Drag to resize the window, keeping its top-left corner fixed.
struct WindowResizeHandle: NSViewRepresentable {
    var minSize: CGSize

    final class HandleView: NSView {
        var minSize: CGSize = .zero
        private var startFrame: NSRect = .zero
        private var startMouse: NSPoint = .zero

        override func mouseDown(with event: NSEvent) {
            startFrame = window?.frame ?? .zero
            startMouse = NSEvent.mouseLocation
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window else { return }
            let p = NSEvent.mouseLocation
            let w = max(minSize.width, startFrame.width + (p.x - startMouse.x))
            let h = max(minSize.height, startFrame.height - (p.y - startMouse.y))
            window.setFrame(NSRect(x: startFrame.minX, y: startFrame.maxY - h, width: w, height: h), display: true)
        }

        override func mouseUp(with event: NSEvent) { window?.invalidateShadow() }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .crosshair)
        }
    }

    func makeNSView(context: Context) -> HandleView {
        let v = HandleView()
        v.minSize = minSize
        return v
    }
    func updateNSView(_ nsView: HandleView, context: Context) { nsView.minSize = minSize }
}
