import SwiftUI
import AppKit

@main
struct NikonScanApp: App {
    @StateObject private var scannerManager = ScannerManager()
    @StateObject private var scanSettings   = ScanSettings()
    @AppStorage("showToolPalette") private var showToolPalette = true
    @AppStorage("showProgressWindow") private var showProgressWindow = true

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(scannerManager)
                .environmentObject(scanSettings)
                .frame(minWidth: 1150, minHeight: 760)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: DesignLayout.defaultSize.width, height: DesignLayout.defaultSize.height)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Scanner") {
                Button("Preview") {
                    Task { await scannerManager.preview(settings: scanSettings) }
                }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(scannerManager.connectedScanner == nil || scannerManager.isBusy)

                Button("Scan") {
                    Task {
                        await scannerManager.scan(settings: scanSettings)
                        scanSettings.cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                    }
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(scannerManager.connectedScanner == nil || scannerManager.isBusy)

                Button("Cancel") {
                    scannerManager.cancelCurrentOperation()
                }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!scannerManager.isBusy)

                Picker("Resolution", selection: $scanSettings.resolution) {
                    ForEach(scannerManager.connectedScanner?.model.availableResolutions ?? [300, 600, 1200, 2400, 4000],
                            id: \.self) { r in
                        Text("\(r) dpi").tag(r)
                    }
                }
                Toggle("Auto Focus", isOn: $scanSettings.autoFocus)

                Divider()

                Button("Eject Film") { scannerManager.eject() }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(scannerManager.connectedScanner == nil || scannerManager.isBusy)

                Divider()

                Button("Reset Settings") { scanSettings.reset() }
            }

            CommandMenu("Tools") {
                Toggle("Tool Palette", isOn: $showToolPalette)
                    .keyboardShortcut("t", modifiers: [.command, .option])
                Toggle("Progress", isOn: $showProgressWindow)
                Toggle("Auto-Align Frame", isOn: $scanSettings.autoAlign)
                Divider()
                Button("Rotate Left") { scanSettings.rotation = (scanSettings.rotation + 270) % 360 }
                    .keyboardShortcut("[", modifiers: .command)
                Button("Rotate Right") { scanSettings.rotation = (scanSettings.rotation + 90) % 360 }
                    .keyboardShortcut("]", modifiers: .command)
            }

            CommandGroup(after: .saveItem) {
                Button("Save Scan...") {
                    NotificationCenter.default.post(name: .nikonSaveRequested, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(scannerManager.previewImage == nil
                          && scannerManager.scannedImage == nil
                          && scannerManager.displayedImage == nil)

                Picker("Save Format", selection: $scanSettings.outputFormat) {
                    ForEach(OutputFormat.allCases) { fmt in
                        Text(fmt.rawValue).tag(fmt)
                    }
                }

                Button("Batch Save Frames...") {
                    do {
                        _ = try scannerManager.saveBatch(settings: scanSettings) { raw in
                            ImageProcessor.apply(settings: scanSettings, to: raw)
                        }
                    } catch ScannerError.saveCancelled {
                        // dismissed
                    } catch {
                        scannerManager.lastError = error.localizedDescription
                    }
                }
                .disabled(scannerManager.scannedFrames.isEmpty && scannerManager.framePreviews.isEmpty)
            }
        }
    }
}
