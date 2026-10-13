import SwiftUI
import AppKit

@main
struct NikonScanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var scannerManager = AppModel.shared.scanner
    @StateObject private var scanSettings   = AppModel.shared.settings
    @StateObject private var windows        = AppModel.shared.windows

    var body: some Scene {
        // The scanner, image, progress and palette windows are free-floating
        // NSWindows managed by WindowManager; this scene only provides Preferences.
        Settings {
            PreferencesView()
                .environmentObject(scanSettings)
                .preferredColorScheme(.light)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Scanner") {
                Button("Preview") { AppModel.shared.workspace.preview() }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(scannerManager.connectedScanner == nil || scannerManager.isBusy)

                Button("Scan") { AppModel.shared.workspace.scan() }
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
                Toggle("Tool Palette", isOn: $windows.showPalette)
                    .keyboardShortcut("t", modifiers: [.command, .option])
                Toggle("Progress", isOn: $windows.showProgress)
                Toggle("Auto-Align Frame", isOn: $scanSettings.autoAlign)
                Divider()
                Button("Rotate Left") { AppModel.shared.workspace.rotate(by: -90) }
                    .keyboardShortcut("[", modifiers: .command)
                Button("Rotate Right") { AppModel.shared.workspace.rotate(by: 90) }
                    .keyboardShortcut("]", modifiers: .command)
                Button("Rotate 180°") { AppModel.shared.workspace.rotate(by: 180) }
                Button("Flip Horizontal") {
                    scanSettings.updateOrientation(frame: scannerManager.selectedFrame) { $0.flipDisplayHorizontal() }
                }
                Button("Flip Vertical") {
                    scanSettings.updateOrientation(frame: scannerManager.selectedFrame) { $0.flipDisplayVertical() }
                }

                Divider()

                Button("Show All Windows") { windows.showAll() }
                    .keyboardShortcut("0", modifiers: .command)
            }

            CommandGroup(after: .saveItem) {
                Button("Save Scan...") {
                    AppModel.shared.workspace.saveCurrentImage()
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
                    AppModel.shared.workspace.saveBatch()
                }
                .disabled(scannerManager.scannedFrames.isEmpty && scannerManager.framePreviews.isEmpty)
            }
        }
    }
}
