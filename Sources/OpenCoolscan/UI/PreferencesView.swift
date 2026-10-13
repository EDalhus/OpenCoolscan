import SwiftUI
import AppKit

struct PreferencesView: View {
    @EnvironmentObject var settings: ScanSettings
    @Environment(\.dismiss) var dismiss

    @AppStorage("scratchDisk") var scratchDisk = ""
    @AppStorage("autoApplyCMS") var autoApplyCMS = true
    @AppStorage("defaultDPI") var defaultDPI = 2400
    @AppStorage("previewDPI") var previewDPI = 600
    @AppStorage("workingColorSpace") var workingColorSpace = "sRGB"
    @AppStorage("monitorProfile") var monitorProfile = "sRGB"
    @AppStorage("autoSaveAfterScan") var autoSaveAfterScan = false
    @AppStorage("scanimagePath") var scanimagePath = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Preferences")
                    .font(.headline)
                Spacer()
                Button("Close") { dismiss() }
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            TabView {
                Form {
                    Section("Scanning Defaults") {
                        Picker("Default Resolution", selection: $defaultDPI) {
                            Text("300 dpi").tag(300)
                            Text("600 dpi").tag(600)
                            Text("1200 dpi").tag(1200)
                            Text("2400 dpi").tag(2400)
                            Text("4000 dpi").tag(4000)
                        }
                        .onChange(of: defaultDPI) { newValue in
                            settings.resolution = newValue
                        }

                        Toggle("Auto-save scans to scratch disk", isOn: $autoSaveAfterScan)
                    }
                    Section("Preview") {
                        Picker("Preview Resolution", selection: $previewDPI) {
                            Text("Low (300 dpi)").tag(300)
                            Text("Medium (600 dpi)").tag(600)
                            Text("High (1200 dpi)").tag(1200)
                        }
                    }
                }
                .formStyle(.grouped)
                .tabItem { Label("General", systemImage: "gearshape") }

                Form {
                    Section("Color Management") {
                        Toggle("Apply color management automatically", isOn: $autoApplyCMS)
                        Picker("Monitor Profile", selection: $monitorProfile) {
                            Text("System Default").tag("sRGB")
                            Text("sRGB IEC61966-2.1").tag("sRGB")
                            Text("Adobe RGB (1998)").tag("Adobe RGB (1998)")
                        }
                        Picker("RGB Working Space", selection: $workingColorSpace) {
                            Text("sRGB").tag("sRGB")
                            Text("Adobe RGB (1998)").tag("Adobe RGB (1998)")
                            Text("Apple RGB").tag("Apple RGB")
                            Text("Grayscale").tag("Grayscale")
                        }
                        .onChange(of: workingColorSpace) { newValue in
                            if let space = ColorSpace(rawValue: newValue) {
                                settings.colorSpace = space
                            }
                        }
                    }
                }
                .formStyle(.grouped)
                .tabItem { Label("Color", systemImage: "paintpalette") }

                Form {
                    Section("Scratch Disk") {
                        Text("Used for temporary scan files and optional auto-save.")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        HStack {
                            TextField("Scratch disk path", text: $scratchDisk)
                                .textFieldStyle(.roundedBorder)
                            Button("Choose...") {
                                let panel = NSOpenPanel()
                                panel.canChooseDirectories = true
                                panel.canChooseFiles = false
                                if panel.runModal() == .OK, let url = panel.url {
                                    scratchDisk = url.path
                                }
                            }
                        }
                    }
                    Section("SANE / scanimage") {
                        Text(resolvedScanimageStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            TextField("scanimage path (optional)", text: $scanimagePath)
                                .textFieldStyle(.roundedBorder)
                            Button("Detect") {
                                if let found = ScanimageLocator.find() {
                                    scanimagePath = found
                                    ScanimageLocator.setOverride(found)
                                }
                            }
                            Button("Clear") {
                                scanimagePath = ""
                                ScanimageLocator.setOverride(nil)
                            }
                        }
                        .onChange(of: scanimagePath) { newValue in
                            ScanimageLocator.setOverride(newValue.isEmpty ? nil : newValue)
                        }
                    }
                }
                .formStyle(.grouped)
                .tabItem { Label("Storage", systemImage: "internaldrive") }
            }
            .frame(width: 420, height: 320)
        }
        .frame(width: 440, height: 400)
    }

    private var resolvedScanimageStatus: String {
        if let found = ScanimageLocator.find() {
            return "Found: \(found)"
        }
        return "scanimage not found. Install SANE (brew install sane-backends) and coolscan3."
    }
}
