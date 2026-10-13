import Foundation
import IOKit
import IOKit.usb
import AppKit
import UniformTypeIdentifiers

@MainActor
class ScannerManager: ObservableObject {
    @Published var availableScanners: [ScannerDevice] = []
    @Published var connectedScanner: ScannerDevice?
    @Published var isScanning = false
    @Published var isPreviewScanning = false
    @Published var isAutoPreviewingAll = false
    @Published var scanProgress: Double = 0
    @Published var statusMessage: String = "No scanner connected" {
        didSet {
            guard statusMessage != oldValue, !statusMessage.isEmpty else { return }
            log.append(LogEntry(date: Date(), message: statusMessage))
            if log.count > 500 { log.removeFirst(log.count - 500) }
        }
    }
    @Published var previewImage: NSImage?
    @Published var scannedImage: NSImage?
    /// Last processed image shown in the UI (used by menu Save).
    @Published var displayedImage: NSImage?
    @Published var lastError: String?

    // Film strip state
    @Published var selectedFrame: Int = 0
    @Published var selectedFrames: Set<Int> = [0]
    @Published var totalFrames: Int = 6
    @Published var framePreviews: [Int: NSImage] = [:]
    /// Full-resolution scans kept for batch export.
    @Published var scannedFrames: [Int: NSImage] = [:]

    // Job state shown by the Progress window and frame badges
    /// Frames of the most recent batch scan, in scan order.
    @Published var scanQueue: [Int] = []
    /// Frame currently being previewed or scanned.
    @Published var currentScanFrame: Int?
    @Published var currentFrameProgress: Double = 0
    @Published var operationStartedAt: Date?
    @Published var log: [LogEntry] = []

    struct LogEntry: Identifiable {
        let id = UUID()
        let date: Date
        let message: String
    }

    enum FrameJobState: Equatable {
        case idle, waiting, active(Double), done
    }

    func jobState(for frame: Int) -> FrameJobState {
        if frame == currentScanFrame { return .active(currentFrameProgress) }
        if isScanning, let cur = currentScanFrame,
           let ci = scanQueue.firstIndex(of: cur),
           let fi = scanQueue.firstIndex(of: frame), fi > ci {
            return .waiting
        }
        if isAutoPreviewingAll, framePreviews[frame] == nil { return .waiting }
        return scannedFrames[frame] != nil ? .done : .idle
    }

    static let nikonVendorID: UInt16 = 0x04B0

    private var usbNotificationPort: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0
    private var usbSelfPtr: UnsafeMutableRawPointer?
    private var activeDriver: NikonMAIDDriver?
    private var activeTask: Task<Void, Never>?

    var isBusy: Bool {
        isScanning || isPreviewScanning || isAutoPreviewingAll
    }

    init() {
        startUSBMonitoring()
        availableScanners.append(ScannerDevice.simulated)
    }

    deinit {
        // Best-effort teardown (cannot hop to MainActor from deinit reliably).
        if let port = usbNotificationPort {
            if addedIterator != 0 { IOObjectRelease(addedIterator) }
            if removedIterator != 0 { IOObjectRelease(removedIterator) }
            IONotificationPortDestroy(port)
        }
        if let ptr = usbSelfPtr {
            Unmanaged<ScannerManager>.fromOpaque(ptr).release()
        }
    }

    // MARK: - USB Monitoring

    func startUSBMonitoring() {
        scanForConnectedDevices()

        usbNotificationPort = IONotificationPortCreate(kIOMainPortDefault)
        guard let port = usbNotificationPort else { return }

        let runLoopSource = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)

        let selfPtr = Unmanaged.passRetained(self).toOpaque()
        usbSelfPtr = selfPtr

        guard let addDict = IOServiceMatching("IOUSBHostDevice") else { return }
        IOServiceAddMatchingNotification(
            port, kIOFirstMatchNotification, addDict,
            { ctx, it in
                guard let ctx else { return }
                let mgr = Unmanaged<ScannerManager>.fromOpaque(ctx).takeUnretainedValue()
                Task { @MainActor in mgr.deviceAdded(iterator: it) }
            },
            selfPtr, &addedIterator
        )
        deviceAdded(iterator: addedIterator)

        guard let removeDict = IOServiceMatching("IOUSBHostDevice") else { return }
        IOServiceAddMatchingNotification(
            port, kIOTerminatedNotification, removeDict,
            { ctx, it in
                guard let ctx else { return }
                let mgr = Unmanaged<ScannerManager>.fromOpaque(ctx).takeUnretainedValue()
                Task { @MainActor in mgr.deviceRemoved(iterator: it) }
            },
            selfPtr, &removedIterator
        )
        deviceRemoved(iterator: removedIterator)
    }

    func scanForConnectedDevices() {
        guard let matchingDict = IOServiceMatching("IOUSBHostDevice") else { return }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
            if let device = scannerDevice(from: service),
               !availableScanners.contains(where: { $0.locationID == device.locationID }) {
                availableScanners.append(device)
                statusMessage = "\(device.name) found"
            }
        }
    }

    private func deviceAdded(iterator: io_iterator_t) {
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            if let device = scannerDevice(from: service) {
                if !availableScanners.contains(where: { $0.locationID == device.locationID }) {
                    availableScanners.append(device)
                    statusMessage = "\(device.name) connected"
                }
            }
        }
    }

    private func deviceRemoved(iterator: io_iterator_t) {
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            guard let locRef = IORegistryEntryCreateCFProperty(
                service, "locationID" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? NSNumber else { continue }

            let locationID = locRef.uint32Value
            availableScanners.removeAll { $0.locationID == locationID }
            if connectedScanner?.locationID == locationID {
                connectedScanner = nil
                statusMessage = "Scanner disconnected"
            }
        }
    }

    private func scannerDevice(from service: io_service_t) -> ScannerDevice? {
        guard let vendorRef = IORegistryEntryCreateCFProperty(
            service, "idVendor" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? NSNumber,
        let productIDRef = IORegistryEntryCreateCFProperty(
            service, "idProduct" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? NSNumber,
        let locationIDRef = IORegistryEntryCreateCFProperty(
            service, "locationID" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? NSNumber
        else { return nil }

        guard vendorRef.uint32Value == UInt32(ScannerManager.nikonVendorID) else { return nil }

        let pid = UInt16(productIDRef.uint32Value)
        let locationID = locationIDRef.uint32Value

        let productName =
            (IORegistryEntryCreateCFProperty(service, "USB Product Name" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String)
            ?? (IORegistryEntryCreateCFProperty(service, "kUSBProductString" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String)
            ?? (IORegistryEntryCreateCFProperty(service, "Product Name" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String)

        guard let model = ScannerModel.resolve(productID: pid, productName: productName) else {
            return nil
        }

        return ScannerDevice(id: UUID(), model: model, isConnected: true, locationID: locationID)
    }

    // MARK: - Connection

    func selectFrame(_ i: Int, cmd: Bool = false, shift: Bool = false) {
        if shift, !selectedFrames.isEmpty {
            let lo = min(selectedFrame, i)
            let hi = max(selectedFrame, i)
            selectedFrames = Set(lo...hi)
            selectedFrame = i
        } else if cmd {
            if selectedFrames.contains(i) {
                selectedFrames.remove(i)
                if selectedFrame == i { selectedFrame = selectedFrames.min() ?? 0 }
                if selectedFrames.isEmpty { selectedFrames = [i]; selectedFrame = i }
            } else {
                selectedFrames.insert(i)
                selectedFrame = i
            }
        } else {
            selectedFrames = [i]
            selectedFrame = i
        }
    }

    func connect(to scanner: ScannerDevice) {
        connectedScanner = scanner
        selectedFrame = 0
        selectedFrames = [0]
        framePreviews = [:]
        scannedFrames = [:]
        scanQueue = []
        totalFrames = 6

        if scanner.model == .simulated {
            statusMessage = "\(scanner.name) ready"
            return
        }

        // Verify SANE can see a Coolscan so the user gets feedback before Preview/Scan.
        statusMessage = "Checking SANE for \(scanner.name)..."
        Task {
            let result = await Task.detached {
                ScanimageLocator.listDevices()
            }.value
            if result.ok {
                statusMessage = "\(scanner.name) ready (SANE OK)"
            } else {
                statusMessage = "\(scanner.name) selected — SANE sees no Coolscan (power on / USB?)"
                // Soft warning only; keep selection so reconnect works when plugged in.
                lastError = """
                SANE did not list a Coolscan scanner.

                Right now this Mac has no Nikon USB device connected.
                Power on the scanner, plug it into USB, then run Preview again —
                or choose “Simulated Scanner” to test without hardware.

                Terminal check: scanimage -L
                """
            }
        }
    }

    func disconnect() {
        cancelCurrentOperation()
        connectedScanner = nil
        statusMessage = "No scanner connected"
        selectedFrame = 0
        selectedFrames = [0]
        framePreviews = [:]
        scannedFrames = [:]
        totalFrames = 6
    }

    // MARK: - Cancel

    func cancelCurrentOperation() {
        activeDriver?.cancel()
        activeTask?.cancel()
        activeTask = nil
        activeDriver = nil
        if isBusy {
            statusMessage = "Cancelled"
        }
        isScanning = false
        isPreviewScanning = false
        isAutoPreviewingAll = false
        scanProgress = 0
        currentScanFrame = nil
        operationStartedAt = nil
    }

    // MARK: - Scanning

    func preview(settings: ScanSettings) async {
        guard let scanner = connectedScanner else {
            lastError = "No scanner connected"
            return
        }
        guard !isBusy else { return }

        isPreviewScanning = true
        scanProgress = 0
        currentScanFrame = selectedFrame
        currentFrameProgress = 0
        operationStartedAt = Date()
        statusMessage = "Preview scanning frame \(selectedFrame + 1)..."
        defer {
            isPreviewScanning = false
            scanProgress = 0
            currentScanFrame = nil
            operationStartedAt = nil
            activeDriver = nil
        }

        do {
            let image: NSImage
            let frameNumber = selectedFrame + 1
            if scanner.model == .simulated {
                image = try await SimulatedScanner.preview(settings: settings, frame: selectedFrame) { [weak self] p in
                    Task { @MainActor in self?.scanProgress = p; self?.currentFrameProgress = p }
                }
            } else {
                let driver = NikonMAIDDriver(device: scanner)
                activeDriver = driver
                do {
                    image = try await driver.preview(settings: settings, frame: frameNumber) { [weak self] p in
                        Task { @MainActor in self?.scanProgress = p; self?.currentFrameProgress = p }
                    }
                } catch ScannerError.frameOptionInactive where frameNumber > 1 {
                    statusMessage = "Frame select unavailable, scanning loaded frame..."
                    image = try await driver.preview(settings: settings, frame: 1) { [weak self] p in
                        Task { @MainActor in self?.scanProgress = p; self?.currentFrameProgress = p }
                    }
                }
            }
            previewImage = image
            framePreviews[selectedFrame] = image
            statusMessage = "Preview complete"
            reportActualResolution(settings)
        } catch is CancellationError {
            statusMessage = "Preview cancelled"
        } catch ScannerError.cancelled {
            statusMessage = "Preview cancelled"
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Preview failed: \(error.localizedDescription)"
        }
    }

    func scan(settings: ScanSettings) async {
        guard let scanner = connectedScanner else {
            lastError = "No scanner connected"
            return
        }
        guard !isBusy else { return }

        let framesToScan = selectedFrames.sorted()

        isScanning = true
        scanProgress = 0
        scanQueue = framesToScan
        operationStartedAt = Date()
        defer {
            isScanning = false
            scanProgress = 0
            currentScanFrame = nil
            operationStartedAt = nil
            activeDriver = nil
        }
        let total = framesToScan.count
        var successCount = 0

        for (idx, frameIndex) in framesToScan.enumerated() {
            try? Task.checkCancellation()
            if Task.isCancelled {
                statusMessage = "Scan cancelled"
                return
            }

            let frameNumber = frameIndex + 1
            currentScanFrame = frameIndex
            currentFrameProgress = 0
            if total > 1 {
                statusMessage = "Scanning frame \(frameIndex + 1) (\(idx + 1)/\(total)) at \(settings.resolution) dpi..."
            } else {
                statusMessage = "Scanning frame \(frameIndex + 1) at \(settings.resolution) dpi..."
            }
            do {
                let image: NSImage
                if scanner.model == .simulated {
                    image = try await SimulatedScanner.scan(settings: settings, frame: frameIndex) { [weak self] p in
                        let overall = (Double(idx) + p) / Double(total)
                        Task { @MainActor in self?.scanProgress = overall; self?.currentFrameProgress = p }
                    }
                } else {
                    let driver = NikonMAIDDriver(device: scanner)
                    activeDriver = driver
                    do {
                        image = try await driver.scan(settings: settings, frame: frameNumber) { [weak self] p in
                            let overall = (Double(idx) + p) / Double(total)
                            Task { @MainActor in self?.scanProgress = overall; self?.currentFrameProgress = p }
                        }
                    } catch ScannerError.frameOptionInactive where frameNumber > 1 {
                        image = try await driver.scan(settings: settings, frame: 1) { [weak self] p in
                            let overall = (Double(idx) + p) / Double(total)
                            Task { @MainActor in self?.scanProgress = overall; self?.currentFrameProgress = p }
                        }
                    }
                }
                scannedImage = image
                scannedFrames[frameIndex] = image
                framePreviews[frameIndex] = image
                successCount += 1
            } catch is CancellationError {
                statusMessage = "Scan cancelled"
                return
            } catch ScannerError.cancelled {
                statusMessage = "Scan cancelled"
                return
            } catch {
                lastError = error.localizedDescription
                statusMessage = "Scan failed on frame \(frameIndex + 1): \(error.localizedDescription)"
                return
            }
        }

        reportActualResolution(settings)
        statusMessage = successCount > 1
            ? "Scan complete (\(successCount) frames)"
            : "Scan complete"

        if UserDefaults.standard.bool(forKey: "autoSaveAfterScan"), successCount > 0 {
            await autoSaveScannedFrames(settings: settings)
        }
    }

    func autoPreviewAllFrames(settings: ScanSettings) async {
        guard let scanner = connectedScanner else {
            lastError = "No scanner connected"
            return
        }
        guard !isBusy else { return }

        isAutoPreviewingAll = true
        scanProgress = 0
        operationStartedAt = Date()
        defer {
            isAutoPreviewingAll = false
            scanProgress = 0
            currentScanFrame = nil
            operationStartedAt = nil
            activeDriver = nil
        }

        if scanner.model == .simulated {
            statusMessage = "Auto-preview: querying frames..."
            for i in 0..<6 {
                if Task.isCancelled { statusMessage = "Cancelled"; return }
                statusMessage = "Auto-preview: frame \(i + 1)/6..."
                scanProgress = Double(i) / 6.0
                currentScanFrame = i
                do {
                    let image = try await SimulatedScanner.preview(settings: settings, frame: i) { [weak self] p in
                        Task { @MainActor in self?.currentFrameProgress = p }
                    }
                    framePreviews[i] = image
                } catch { break }
            }
            totalFrames = 6
            selectedFrame = 0
            statusMessage = "Auto-preview complete (6 frames)"
            return
        }

        let driver = NikonMAIDDriver(device: scanner)
        activeDriver = driver

        let maxFrames = 36
        var scannedCount = 0
        totalFrames = 6

        for i in 0..<maxFrames {
            if Task.isCancelled { statusMessage = "Cancelled"; return }
            statusMessage = "Auto-preview: frame \(i + 1)..."
            scanProgress = Double(i) / Double(maxFrames)
            currentScanFrame = i
            do {
                let image = try await driver.preview(settings: settings, frame: i + 1) { _ in }
                framePreviews[i] = image
                scannedCount += 1
                totalFrames = scannedCount
            } catch ScannerError.frameOptionInactive {
                if scannedCount == 0 {
                    lastError = "Frame selection not supported in current holder mode"
                }
                break
            } catch ScannerError.cancelled {
                statusMessage = "Cancelled"
                return
            } catch {
                break
            }
        }

        if selectedFrame >= totalFrames { selectedFrame = 0 }
        statusMessage = scannedCount > 0
            ? "Auto-preview complete (\(scannedCount) frame\(scannedCount == 1 ? "" : "s"))"
            : "Auto-preview: no frames found"
    }

    func eject() {
        guard let scanner = connectedScanner else { return }
        if scanner.model == .simulated {
            statusMessage = "Film ejected (simulated)"
        } else {
            statusMessage = "Ejecting film..."
            let driver = NikonMAIDDriver(device: scanner)
            Task {
                await driver.eject()
                await MainActor.run {
                    self.statusMessage = "Film ejected"
                }
            }
        }
        framePreviews = [:]
        scannedFrames = [:]
        scanQueue = []
        totalFrames = 6
        selectedFrame = 0
        selectedFrames = [0]
    }

    // MARK: - Save

    func saveImage(_ image: NSImage, settings: ScanSettings) throws -> URL {
        let panel = NSSavePanel()
        if let utType = UTType(settings.outputFormat.utTypeIdentifier) {
            panel.allowedContentTypes = [utType]
        } else if let utType = UTType(filenameExtension: settings.outputFormat.fileExtension) {
            panel.allowedContentTypes = [utType]
        }
        panel.nameFieldStringValue = defaultFileName(settings: settings, frame: selectedFrame)

        guard panel.runModal() == .OK, let url = panel.url else {
            throw ScannerError.saveCancelled
        }

        try writeImage(image, to: url, settings: settings)
        return url
    }

    /// Batch-save all frames in `scannedFrames` (or selected previews) into a chosen folder.
    func saveBatch(settings: ScanSettings, processed: (NSImage) -> NSImage) throws -> Int {
        let frames = scannedFrames.isEmpty
            ? selectedFrames.compactMap { idx -> (Int, NSImage)? in
                guard let img = framePreviews[idx] else { return nil }
                return (idx, img)
            }
            : scannedFrames.sorted(by: { $0.key < $1.key }).map { ($0.key, $0.value) }

        guard !frames.isEmpty else {
            throw ScannerError.imageConversionFailed
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Save Here"
        panel.message = "Choose a folder for \(frames.count) scan(s)"

        guard panel.runModal() == .OK, let dir = panel.url else {
            throw ScannerError.saveCancelled
        }

        var saved = 0
        let stamp = Int(Date().timeIntervalSince1970)
        for (index, raw) in frames {
            let image = processed(raw)
            let name = "Scan_\(stamp)_frame\(String(format: "%02d", index + 1)).\(settings.outputFormat.fileExtension)"
            let url = dir.appendingPathComponent(name)
            try writeImage(image, to: url, settings: settings)
            saved += 1
        }
        statusMessage = "Saved \(saved) file(s) to \(dir.lastPathComponent)"
        return saved
    }

    private func autoSaveScannedFrames(settings: ScanSettings) async {
        let scratch = ScanimageLocator.scratchDirectory
            .appendingPathComponent("AutoSave", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970)
        var count = 0
        for (index, image) in scannedFrames.sorted(by: { $0.key < $1.key }) {
            let url = scratch.appendingPathComponent(
                "Scan_\(stamp)_frame\(String(format: "%02d", index + 1)).\(settings.outputFormat.fileExtension)"
            )
            do {
                try writeImage(image, to: url, settings: settings)
                count += 1
            } catch {
                lastError = "Auto-save failed: \(error.localizedDescription)"
                return
            }
        }
        if count > 0 {
            statusMessage = "Auto-saved \(count) file(s) to \(scratch.path)"
        }
    }

    private func writeImage(_ image: NSImage, to url: URL, settings: ScanSettings) throws {
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else {
            throw ScannerError.imageConversionFailed
        }

        let data: Data?
        switch settings.outputFormat {
        case .tiff:
            data = bitmapRep.representation(using: .tiff, properties: [:])
        case .jpeg:
            data = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.92])
        case .png:
            data = bitmapRep.representation(using: .png, properties: [:])
        }

        guard let data, !data.isEmpty else {
            throw ScannerError.imageConversionFailed
        }
        try data.write(to: url, options: .atomic)
    }

    private func defaultFileName(settings: ScanSettings, frame: Int) -> String {
        let stamp = Int(Date().timeIntervalSince1970)
        return "Scan_\(stamp)_f\(frame + 1).\(settings.outputFormat.fileExtension)"
    }

    private func reportActualResolution(_ settings: ScanSettings) {
        let actual = NikonMAIDDriver.saneResolutions
            .min(by: { abs($0 - settings.resolution) < abs($1 - settings.resolution) })
            ?? settings.resolution
        if actual != settings.resolution {
            statusMessage += " (SANE used \(actual) dpi)"
        }
    }
}

enum ScannerError: LocalizedError {
    case noDevice
    case communicationFailed(String)
    case saveCancelled
    case imageConversionFailed
    case noFilmLoaded
    case frameOptionInactive
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noDevice:                     return "No scanner device found"
        case .communicationFailed(let msg): return "Communication error: \(msg)"
        case .saveCancelled:                return "Save cancelled"
        case .imageConversionFailed:        return "Image conversion failed"
        case .noFilmLoaded:                 return "No film loaded — insert a film strip or slide and try again"
        case .frameOptionInactive:          return "Frame selection not supported in current holder mode"
        case .cancelled:                    return "Operation cancelled"
        }
    }
}
