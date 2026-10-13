import AppKit
import UniformTypeIdentifiers
import CoolscanKit

// Save dialogs are app UI, so they live here rather than in CoolscanKit.
extension ScannerManager {
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
    func saveBatch(settings: ScanSettings, processed: (Int, NSImage) -> NSImage) throws -> Int {
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
            let image = processed(index, raw)
            let name = "Scan_\(stamp)_frame\(String(format: "%02d", index + 1)).\(settings.outputFormat.fileExtension)"
            let url = dir.appendingPathComponent(name)
            try writeImage(image, to: url, settings: settings)
            saved += 1
        }
        statusMessage = "Saved \(saved) file(s) to \(dir.lastPathComponent)"
        return saved
    }
}
