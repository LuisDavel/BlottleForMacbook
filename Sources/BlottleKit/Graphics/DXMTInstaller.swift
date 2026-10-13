import Foundation

/// Installs a DXMT release (Direct3D 11 → Metal) into an engine + bottle.
///
/// DXMT ships Windows DLLs (`d3d11.dll`, `dxgi.dll`, `winemetal.dll`) and a
/// Unix helper (`winemetal.so`). The DLLs go in the bottle's `system32`, the
/// `.so` next to Wine's other Unix libraries. Experimental: layouts change
/// between releases, so files are placed by extension.
public enum DXMTInstaller {
    public static let releasesPage = URL(string: "https://github.com/3Shain/dxmt/releases")!

    @discardableResult
    public static func install(archive: URL, into bottle: Bottle, engine: WineEngine) async throws -> [String] {
        guard bottle.isInitialized else {
            throw BlottleError.notSupported("a garrafa ainda não foi inicializada")
        }
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("blottle-dxmt-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        try await Archive.extract(archive, to: scratch)

        let fm = FileManager.default
        var installed: [String] = []
        guard let enumerator = fm.enumerator(at: scratch, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        for case let file as URL in enumerator {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let name = file.lastPathComponent
            let lowered = name.lowercased()
            let pathLowered = file.path.lowercased()
            // Skip 32-bit copies: Apple Silicon Wine only runs 64-bit DXMT.
            if pathLowered.contains("/x32/") || pathLowered.contains("/i386/") || pathLowered.contains("/x86/") {
                continue
            }
            if lowered.hasSuffix(".dll") {
                try replace(file, at: bottle.system32.appendingPathComponent(name), backupSuffix: DXVKInstaller.backupSuffix)
                installed.append(name)
            } else if lowered.hasSuffix(".so") {
                try fm.createDirectory(at: engine.unixLibDirectory, withIntermediateDirectories: true)
                try replace(file, at: engine.unixLibDirectory.appendingPathComponent(name), backupSuffix: ".bak")
                installed.append(name)
            } else if lowered == "dxmt.conf" {
                try replace(file, at: bottle.driveC.appendingPathComponent(name), backupSuffix: ".bak")
                installed.append(name)
            }
        }
        guard installed.contains(where: { $0.lowercased() == "d3d11.dll" }) else {
            throw BlottleError.parseError("o pacote não contém d3d11.dll")
        }
        return installed
    }

    static func replace(_ source: URL, at destination: URL, backupSuffix: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path) {
            let backup = URL(fileURLWithPath: destination.path + backupSuffix)
            if !fm.fileExists(atPath: backup.path) {
                try fm.moveItem(at: destination, to: backup)
            } else {
                try fm.removeItem(at: destination)
            }
        }
        try fm.copyItem(at: source, to: destination)
    }
}
