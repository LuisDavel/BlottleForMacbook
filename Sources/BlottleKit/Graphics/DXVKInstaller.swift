import Foundation

/// Installs Gcenx's DXVK-macOS DLLs into a bottle (DirectX 10/11 over MoltenVK).
public enum DXVKInstaller {
    public static let defaultArchiveURL = URL(string:
        "https://github.com/Gcenx/DXVK-macOS/releases/download/v1.10.3-20230507-repack/dxvk-macOS-async-v1.10.3-20230507-repack.tar.gz")!

    static let markerFileName = ".blottle-dxvk"
    static let backupSuffix = ".wined3d"

    public static func isInstalled(in bottle: Bottle) -> Bool {
        FileManager.default.fileExists(atPath: bottle.url.appendingPathComponent(markerFileName).path)
    }

    /// Copies the DLLs from `archive` (downloaded when nil) into `system32`/`syswow64`.
    /// Returns the DLL names that were installed.
    @discardableResult
    public static func install(
        into bottle: Bottle,
        archive: URL? = nil,
        progress: ((InstallProgress) -> Void)? = nil
    ) async throws -> [String] {
        guard bottle.isInitialized else {
            throw BlottleError.notSupported("a garrafa ainda não foi inicializada")
        }
        let archiveURL: URL
        if let archive {
            archiveURL = archive
        } else {
            archiveURL = try await Downloader.cached(defaultArchiveURL) { progress?(.downloading($0)) }
        }
        progress?(.extracting)
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("blottle-dxvk-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        try await Archive.extract(archiveURL, to: scratch)

        progress?(.finishing)
        var installed: [String] = []
        let x64 = Archive.find(named: "x64", under: scratch)
        let x32 = Archive.find(named: "x32", under: scratch)
        guard x64 != nil || x32 != nil else {
            throw BlottleError.parseError("o pacote DXVK não contém as pastas x64/x32")
        }
        if let x64 {
            installed += try copyDLLs(from: x64, to: bottle.system32)
        }
        if let x32, bottle.hasWOW64 {
            _ = try copyDLLs(from: x32, to: bottle.sysWOW64)
        }
        try installed.joined(separator: "\n").write(
            to: bottle.url.appendingPathComponent(markerFileName),
            atomically: true,
            encoding: .utf8
        )
        return installed
    }

    /// Restores the Wine built-in DLLs that were replaced.
    public static func uninstall(from bottle: Bottle) throws {
        for directory in [bottle.system32, bottle.sysWOW64] {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { continue }
            for entry in entries where entry.hasSuffix(backupSuffix) {
                let original = directory.appendingPathComponent(String(entry.dropLast(backupSuffix.count)))
                let backup = directory.appendingPathComponent(entry)
                try? FileManager.default.removeItem(at: original)
                try FileManager.default.moveItem(at: backup, to: original)
            }
        }
        try? FileManager.default.removeItem(at: bottle.url.appendingPathComponent(markerFileName))
    }

    static func copyDLLs(from source: URL, to destination: URL) throws -> [String] {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        var names: [String] = []
        for entry in try fm.contentsOfDirectory(atPath: source.path) where entry.lowercased().hasSuffix(".dll") {
            let target = destination.appendingPathComponent(entry)
            let backup = destination.appendingPathComponent(entry + backupSuffix)
            if fm.fileExists(atPath: target.path), !fm.fileExists(atPath: backup.path) {
                try fm.moveItem(at: target, to: backup)
            } else if fm.fileExists(atPath: target.path) {
                try fm.removeItem(at: target)
            }
            try fm.copyItem(at: source.appendingPathComponent(entry), to: target)
            names.append(String(entry.dropLast(4)).lowercased())
        }
        return names
    }
}
