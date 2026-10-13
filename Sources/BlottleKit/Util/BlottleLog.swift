import Foundation

/// Per-launch log files under `~/Library/Logs/Blottle/<bottle>/`.
public enum BlottleLog {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()

    public static func directory(forBottle name: String) -> URL {
        BlottlePaths.logs.appendingPathComponent(sanitize(name), isDirectory: true)
    }

    /// Maximum number of `.log` files kept per bottle (oldest are pruned on `open`).
    public static var maxFilesPerBottle = 40

    /// Creates a fresh log file and returns a handle open for writing.
    public static func open(bottle: String, name: String) throws -> (url: URL, handle: FileHandle) {
        let directory = directory(forBottle: bottle)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Leave room for the file about to be created so the total stays <= max.
        prune(directory: directory, keep: max(maxFilesPerBottle - 1, 0))
        let fileName = "\(sanitize(name))-\(formatter.string(from: Date())).log"
        let url = directory.appendingPathComponent(fileName)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        return (url, handle)
    }

    /// Deletes the oldest `.log` files of a bottle beyond `keep`.
    public static func prune(bottle: String, keep: Int = maxFilesPerBottle) {
        prune(directory: directory(forBottle: bottle), keep: keep)
    }

    /// Deletes the oldest `.log` files in `directory` beyond `keep`, by modification date.
    static func prune(directory: URL, keep: Int) {
        let keep = max(keep, 0)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let logs = files.filter { $0.pathExtension == "log" }
        guard logs.count > keep else { return }
        let dated = logs.map { url -> (URL, Date) in
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return (url, date)
        }
        for (url, _) in dated.sorted(by: { $0.1 > $1.1 }).dropFirst(keep) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Most recent log files for a bottle, newest first.
    public static func recent(bottle: String, limit: Int = 20) -> [URL] {
        let directory = directory(forBottle: bottle)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        let dated = files.map { url -> (URL, Date) in
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return (url, date)
        }
        return dated.sorted { $0.1 > $1.1 }.prefix(limit).map { $0.0 }
    }

    public static func sanitize(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_. "))
        let cleaned = name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let result = String(cleaned).trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? "bottle" : result
    }
}
