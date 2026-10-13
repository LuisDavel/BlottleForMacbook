import Foundation

/// Converts between Windows paths (`C:\Games\x.exe`) and the Unix paths inside a prefix.
public enum WinePath {
    public static func toUnix(_ windowsPath: String, bottle: Bottle) -> URL? {
        let normalized = windowsPath.replacingOccurrences(of: "/", with: "\\")
        guard normalized.count >= 2 else { return nil }
        let characters = Array(normalized)
        guard characters[1] == ":", characters[0].isLetter else {
            // Already a Unix path?
            if normalized.hasPrefix("\\") == false, windowsPath.hasPrefix("/") {
                return URL(fileURLWithPath: windowsPath)
            }
            return nil
        }
        let drive = String(characters[0]).lowercased()
        var rest = String(characters.dropFirst(2))
        if rest.hasPrefix("\\") { rest.removeFirst() }
        let components = rest.split(separator: "\\", omittingEmptySubsequences: true).map(String.init)

        var base: URL
        if drive == "c" {
            base = bottle.driveC
        } else {
            base = bottle.dosDevices.appendingPathComponent("\(drive):", isDirectory: true)
        }
        for component in components {
            base.appendPathComponent(component)
        }
        return base
    }

    public static func toWindows(_ url: URL, bottle: Bottle) -> String? {
        let driveC = bottle.driveC.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path == driveC {
            return "C:\\"
        }
        guard path.hasPrefix(driveC + "/") else { return nil }
        let rest = path.dropFirst(driveC.count + 1)
        return "C:\\" + rest.replacingOccurrences(of: "/", with: "\\")
    }
}
