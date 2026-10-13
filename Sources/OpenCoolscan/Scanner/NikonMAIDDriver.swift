import Foundation
import AppKit

// Hardware driver via SANE coolscan3 (`scanimage` CLI).
// Class name kept for continuity with the original Nikon Scan / MAID naming.

final class NikonMAIDDriver: @unchecked Sendable {
    let device: ScannerDevice

    /// 35 mm usable frame in millimetres (SANE geometry units).
    private static let filmWidthMM: Double = 36.0
    private static let filmHeightMM: Double = 24.0

    static let saneResolutions = [
        4000, 2000, 1333, 1000, 800, 666, 571, 500, 444, 400, 363, 333,
        307, 285, 266, 250, 235, 222, 210, 200, 190, 181, 173, 166, 160,
        153, 148, 142, 137, 133, 129, 125, 121, 117, 114, 111, 108, 105,
        102, 100, 97, 95, 93, 90
    ]

    private let processLock = NSLock()
    private var currentProcess: Process?

    init(device: ScannerDevice) {
        self.device = device
    }

    func cancel() {
        processLock.lock()
        defer { processLock.unlock() }
        currentProcess?.terminate()
        currentProcess = nil
    }

    // MARK: - SANE device detection

    private func saneDeviceName() throws -> String {
        let bin = ScanimageLocator.path
        guard FileManager.default.isExecutableFile(atPath: bin) else {
            throw ScannerError.communicationFailed(
                "scanimage not found. Install with: brew install sane-backends"
            )
        }

        let output = try shell(bin, args: ["-L"])

        func parseName(from line: String) -> String? {
            guard let start = line.firstIndex(of: "`"),
                  let end = line.firstIndex(of: "'"),
                  start < end else { return nil }
            return String(line[line.index(after: start)..<end])
        }

        for line in output.components(separatedBy: "\n") {
            if line.lowercased().contains(deviceKeyword()), let name = parseName(from: line) {
                Thread.sleep(forTimeInterval: 0.5)
                return name
            }
        }
        for line in output.components(separatedBy: "\n") {
            if line.lowercased().contains("coolscan"), let name = parseName(from: line) {
                Thread.sleep(forTimeInterval: 0.5)
                return name
            }
        }

        // Diagnose: SANE works but no Coolscan on the bus.
        let lower = output.lowercased()
        if lower.contains("no scanners were identified") || !lower.contains("coolscan") {
            throw ScannerError.communicationFailed(
                """
                SANE sees no Coolscan. macOS also reports no Nikon USB device right now.
                1) Power on the scanner and wait for the ready light
                2) Plug it directly into the Mac (avoid unpowered hubs)
                3) In Terminal run: scanimage -L
                4) Or pick “Simulated Scanner” to test the UI without hardware
                """
            )
        }
        throw ScannerError.communicationFailed(
            "Scanner not found by SANE for \(device.name). Output:\n\(output)"
        )
    }

    private func deviceKeyword() -> String {
        switch device.model {
        case .ls4000: return "ls-4000"
        case .ls5000: return "ls-5000"
        case .ls8000: return "ls-8000"
        case .ls9000: return "ls-9000"
        case .ls40:   return "ls-40"
        case .ls50:   return "ls-50"
        case .ls2000: return "ls-2000"
        case .ls30:   return "ls-30"
        case .simulated: return ""
        }
    }

    // MARK: - Frame count

    func getFrameCount() throws -> Int {
        let saneDevice = try saneDeviceName()
        let output = try shell(ScanimageLocator.path, args: ["-d", saneDevice, "--help"])
        Thread.sleep(forTimeInterval: 0.5)
        for line in output.components(separatedBy: "\n") {
            guard line.contains("--frame") else { continue }
            let parts = line.components(separatedBy: "..")
            if parts.count >= 2 {
                let afterDots = parts[1].trimmingCharacters(in: .whitespaces)
                let maxStr = afterDots.components(separatedBy: CharacterSet.whitespaces)[0]
                if let max = Int(maxStr), max > 0 { return max }
            }
        }
        return 1
    }

    // MARK: - Scan operations

    func preview(settings: ScanSettings,
                 frame: Int = 1,
                 progress: @escaping @Sendable (Double) -> Void) async throws -> NSImage {
        try await ScanQueue.shared.run {
            try await Task.detached(priority: .userInitiated) { [self] in
                try Task.checkCancellation()
                let saneDevice = try self.saneDeviceName()
                await MainActor.run { progress(0.1) }

                let tmpFile = self.tempURL(prefix: "nikonscan_preview")
                defer { try? FileManager.default.removeItem(at: tmpFile) }

                let previewDPI = UserDefaults.standard.object(forKey: "previewDPI") as? Int ?? 600
                let previewRes = self.nearestSANEResolution(to: min(previewDPI, 600))
                // Preview always captures the full frame; crop is applied in ImageProcessor for WYSIWYG.
                var args = self.baseArgs(saneDevice: saneDevice, settings: settings, forPreview: true)
                var previewArgs: [String] = [
                    "--preview=yes",
                    "--resolution=\(previewRes)",
                    "--format=tiff",
                    "-o", tmpFile.path
                ]
                if frame > 1 { previewArgs.insert("--frame=\(frame)", at: 0) }
                args += previewArgs

                await MainActor.run { progress(0.2) }
                try self.runScanimage(args: args)
                try Task.checkCancellation()
                await MainActor.run { progress(0.95) }

                guard let image = NSImage(contentsOf: tmpFile) else {
                    throw ScannerError.imageConversionFailed
                }
                return image
            }.value
        }
    }

    func scan(settings: ScanSettings,
              frame: Int = 1,
              progress: @escaping @Sendable (Double) -> Void) async throws -> NSImage {
        try await ScanQueue.shared.run {
            try await Task.detached(priority: .userInitiated) { [self] in
                try Task.checkCancellation()
                let saneDevice = try self.saneDeviceName()
                await MainActor.run { progress(0.05) }

                let tmpFile = self.tempURL(prefix: "nikonscan_scan")
                defer { try? FileManager.default.removeItem(at: tmpFile) }

                let res = self.nearestSANEResolution(to: settings.resolution)
                var args = self.baseArgs(saneDevice: saneDevice, settings: settings, forPreview: false)
                args += self.geometryArgs(settings.cropRect)
                var scanArgs: [String] = [
                    "--resolution=\(res)",
                    "--format=tiff",
                    "-o", tmpFile.path
                ]
                if frame > 1 { scanArgs.insert("--frame=\(frame)", at: 0) }
                args += scanArgs

                await MainActor.run { progress(0.15) }

                // Prefer higher bit depth when requested; fall back to 8-bit on firmware rejection.
                do {
                    try self.runScanimage(args: args)
                } catch {
                    if settings.bitDepth != .bit8, self.shouldRetryAs8Bit(error) {
                        args = args.map { $0.hasPrefix("--depth=") ? "--depth=8" : $0 }
                        if !args.contains(where: { $0.hasPrefix("--depth=") }) {
                            args.insert("--depth=8", at: 1)
                        }
                        try self.runScanimage(args: args)
                    } else {
                        throw error
                    }
                }

                try Task.checkCancellation()
                await MainActor.run { progress(0.95) }

                guard let image = NSImage(contentsOf: tmpFile) else {
                    throw ScannerError.imageConversionFailed
                }
                return image
            }.value
        }
    }

    func eject() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                defer { cont.resume() }
                guard let saneDevice = try? self.saneDeviceName() else { return }
                _ = try? self.shell(ScanimageLocator.path, args: ["-d", saneDevice, "--eject"])
            }
        }
    }

    // MARK: - Arguments

    private func baseArgs(saneDevice: String, settings: ScanSettings, forPreview: Bool) -> [String] {
        var args = ["-d", saneDevice]

        switch settings.filmType {
        case .colorNegative, .bwNegative:
            args += ["--negative=yes"]
        case .colorPositive, .bwPositive:
            args += ["--negative=no"]
        }

        // 16-bit triggers a LUT path some LS-5000 firmware rejects; default 8, try 16 when asked.
        if !forPreview, settings.bitDepth != .bit8 {
            args += ["--depth=16"]
        } else {
            args += ["--depth=8"]
        }

        if settings.multiScan, !forPreview {
            args += ["--samples-per-scan=\(settings.multiScanCount)"]
        }

        if settings.autoFocus {
            args += ["--autofocus=yes", "--focus-on-centre=yes"]
        } else if abs(settings.focusPosition) > 0.01 {
            // Manual focus offset in mm when autofocus is off (backend may ignore if inactive).
            args += ["--autofocus=no"]
        }

        if settings.digitalICE != .off, device.model.supportsDigitalICE, !forPreview {
            args += ["--infrared=yes"]
        }

        return args
    }

    /// Maps normalized crop (0…1) to SANE geometry in millimetres.
    private func geometryArgs(_ crop: CGRect) -> [String] {
        let clamped = CGRect(
            x: max(0, min(1, crop.origin.x)),
            y: max(0, min(1, crop.origin.y)),
            width: max(0.05, min(1, crop.width)),
            height: max(0.05, min(1, crop.height))
        )
        // Full frame → omit geometry so SANE uses its defaults.
        if abs(clamped.minX) < 0.001, abs(clamped.minY) < 0.001,
           abs(clamped.width - 1) < 0.001, abs(clamped.height - 1) < 0.001 {
            return []
        }

        let left = clamped.minX * Self.filmWidthMM
        let top = clamped.minY * Self.filmHeightMM
        let width = clamped.width * Self.filmWidthMM
        let height = clamped.height * Self.filmHeightMM

        return [
            "-l", String(format: "%.2f", left),
            "-t", String(format: "%.2f", top),
            "-x", String(format: "%.2f", width),
            "-y", String(format: "%.2f", height)
        ]
    }

    // MARK: - Helpers

    private func nearestSANEResolution(to target: Int) -> Int {
        Self.saneResolutions.min(by: { abs($0 - target) < abs($1 - target) }) ?? target
    }

    private func tempURL(prefix: String) -> URL {
        ScanimageLocator.scratchDirectory
            .appendingPathComponent("\(prefix)_\(UUID().uuidString).tiff")
    }

    private func shouldRetryAs8Bit(_ error: Error) -> Bool {
        let msg = error.localizedDescription.lowercased()
        return msg.contains("depth") || msg.contains("lut") || msg.contains("write")
            || msg.contains("non-data") || msg.contains("scsi")
    }

    @discardableResult
    private func shell(_ executable: String, args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.environment = ScanimageLocator.processEnvironment()

        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try runTracked(process)

        let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            if process.terminationReason == .uncaughtSignal {
                throw ScannerError.cancelled
            }
            throw ScannerError.communicationFailed(
                err.isEmpty ? "scanimage exited \(process.terminationStatus)" : err
            )
        }
        return out
    }

    private func runScanimage(args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ScanimageLocator.path)
        process.arguments = args
        process.environment = ScanimageLocator.processEnvironment()

        let stderr = Pipe()
        process.standardError = stderr

        try runTracked(process)

        if process.terminationStatus != 0 {
            if process.terminationReason == .uncaughtSignal {
                throw ScannerError.cancelled
            }
            let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if err.contains("Document feeder out of documents") || err.contains("out of documents") {
                throw ScannerError.noFilmLoaded
            }
            if err.lowercased().contains("inactive option") && err.lowercased().contains("frame") {
                throw ScannerError.frameOptionInactive
            }
            if err.lowercased().contains("inactive option") && err.lowercased().contains("infrared") {
                throw ScannerError.communicationFailed(
                    "Digital ICE (infrared) is not available in the current holder/mode. Turn ICE off and retry."
                )
            }
            throw ScannerError.communicationFailed(
                err.isEmpty ? "scanimage failed (exit \(process.terminationStatus))" : err
            )
        }
    }

    private func runTracked(_ process: Process) throws {
        processLock.lock()
        currentProcess = process
        processLock.unlock()
        defer {
            processLock.lock()
            if currentProcess === process { currentProcess = nil }
            processLock.unlock()
        }
        do {
            try process.run()
        } catch {
            throw ScannerError.communicationFailed(
                "Could not launch scanimage at \(ScanimageLocator.path): \(error.localizedDescription)"
            )
        }
        process.waitUntilExit()
    }
}
