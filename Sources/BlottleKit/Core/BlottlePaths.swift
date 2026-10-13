import Foundation

/// Well-known directories used by Blottle.
///
/// Everything lives under `~/Library/Application Support/Blottle` unless the
/// `BLOTTLE_HOME` environment variable is set (handy for tests and for keeping
/// bottles on an external disk).
public enum BlottlePaths {
    public static let homeOverrideKey = "BLOTTLE_HOME"

    public static var root: URL {
        if let override = ProcessInfo.processInfo.environment[homeOverrideKey], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport.appendingPathComponent("Blottle", isDirectory: true)
    }

    public static var bottles: URL { root.appendingPathComponent("Bottles", isDirectory: true) }
    public static var engines: URL { root.appendingPathComponent("Engines", isDirectory: true) }
    public static var cache: URL { root.appendingPathComponent("Cache", isDirectory: true) }
    public static var tools: URL { root.appendingPathComponent("Tools", isDirectory: true) }

    public static var logs: URL {
        if ProcessInfo.processInfo.environment[homeOverrideKey] != nil {
            return root.appendingPathComponent("Logs", isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Blottle", isDirectory: true)
    }

    public static func ensureDirectories() throws {
        for directory in [root, bottles, engines, cache, tools, logs] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
