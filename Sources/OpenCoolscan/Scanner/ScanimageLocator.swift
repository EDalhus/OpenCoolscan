import Foundation

/// Locates the `scanimage` binary used to talk to SANE coolscan3.
enum ScanimageLocator {
    private static let overrideKey = "scanimagePath"

    /// User-configured override, or the first existing candidate on disk.
    static var path: String {
        if let override = UserDefaults.standard.string(forKey: overrideKey),
           !override.isEmpty,
           FileManager.default.isExecutableFile(atPath: override) {
            return override
        }
        return find() ?? "/opt/homebrew/bin/scanimage"
    }

    static func setOverride(_ path: String?) {
        if let path, !path.isEmpty {
            UserDefaults.standard.set(path, forKey: overrideKey)
        } else {
            UserDefaults.standard.removeObject(forKey: overrideKey)
        }
    }

    static func find() -> String? {
        var candidates: [String] = [
            "/opt/homebrew/bin/scanimage",
            "/usr/local/bin/scanimage",
            "/opt/local/bin/scanimage"
        ]

        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":") {
                candidates.append((dir as NSString).appendingPathComponent("scanimage"))
            }
        }

        // Deduplicate while preserving order
        var seen = Set<String>()
        for candidate in candidates {
            guard !seen.contains(candidate) else { continue }
            seen.insert(candidate)
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    /// Directory for temporary scan files (scratch disk preference, else system temp).
    static var scratchDirectory: URL {
        if let scratch = UserDefaults.standard.string(forKey: "scratchDisk"),
           !scratch.isEmpty {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: scratch, isDirectory: &isDir), isDir.boolValue {
                return URL(fileURLWithPath: scratch, isDirectory: true)
            }
        }
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }

    /// Homebrew / MacPorts SANE config directory (dll.conf, coolscan3.conf).
    static var configDirectory: String? {
        var candidates = [
            "/opt/homebrew/etc/sane.d",
            "/usr/local/etc/sane.d",
            "/opt/local/etc/sane.d"
        ]
        // Resolve Cellar symlink for the installed sane-backends formula
        for base in ["/opt/homebrew/opt/sane-backends/etc/sane.d",
                     "/usr/local/opt/sane-backends/etc/sane.d"] {
            if let resolved = try? FileManager.default.destinationOfSymbolicLink(atPath: base) {
                candidates.append(resolved.hasPrefix("/") ? resolved : (base as NSString).deletingLastPathComponent + "/" + resolved)
            }
            candidates.append(base)
        }
        for dir in candidates {
            let coolscan3 = (dir as NSString).appendingPathComponent("coolscan3.conf")
            if FileManager.default.fileExists(atPath: coolscan3) { return dir }
        }
        for dir in candidates {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue {
                return dir
            }
        }
        return nil
    }

    /// Environment for spawned `scanimage` processes.
    static func processEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let config = configDirectory {
            env["SANE_CONFIG_DIR"] = config
        }
        // Ensure Homebrew lib is findable when the app is launched from Finder
        // (GUI apps often lack the shell PATH / DYLD path).
        let libPaths = [
            "/opt/homebrew/lib",
            "/usr/local/lib",
            "/opt/local/lib"
        ].filter { FileManager.default.fileExists(atPath: $0) }
        if !libPaths.isEmpty {
            let existing = env["DYLD_LIBRARY_PATH"] ?? ""
            let merged = (libPaths + existing.split(separator: ":").map(String.init))
                .filter { !$0.isEmpty }
            // Deduplicate
            var seen = Set<String>()
            env["DYLD_LIBRARY_PATH"] = merged.filter { seen.insert($0).inserted }.joined(separator: ":")
        }
        return env
    }

    /// Quick check: does `scanimage -L` report any coolscan device?
    static func listDevices() -> (ok: Bool, output: String) {
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return (false, "scanimage not found at \(path)")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-L"]
        process.environment = processEnvironment()
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (false, error.localizedDescription)
        }
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let combined = (stdout + "\n" + stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        let found = combined.lowercased().contains("coolscan")
            || combined.contains("`") // device `name'
        return (found, combined)
    }
}
