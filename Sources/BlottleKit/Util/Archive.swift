import Foundation

/// Archive extraction and disk-image mounting using the tools that ship with macOS.
public enum Archive {
    public enum Kind: String, Codable, Sendable {
        case tarXZ = "tar.xz"
        case tarGZ = "tar.gz"
        case tarBZ2 = "tar.bz2"
        case zip
        case dmg

        public static func detect(from url: URL) -> Kind? {
            let name = url.lastPathComponent.lowercased()
            if name.hasSuffix(".tar.xz") || name.hasSuffix(".txz") { return .tarXZ }
            if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") { return .tarGZ }
            if name.hasSuffix(".tar.bz2") || name.hasSuffix(".tbz") { return .tarBZ2 }
            if name.hasSuffix(".zip") { return .zip }
            if name.hasSuffix(".dmg") { return .dmg }
            return nil
        }
    }

    /// Extracts a tarball or zip into `directory` (created if needed).
    public static func extract(_ archive: URL, to directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        switch Kind.detect(from: archive) {
        case .zip:
            try await ProcessRunner.check(
                URL(fileURLWithPath: "/usr/bin/ditto"),
                arguments: ["-x", "-k", archive.path, directory.path]
            )
        case .dmg:
            throw BlottleError.notSupported("use withMountedDiskImage para .dmg")
        default:
            try await ProcessRunner.check(
                URL(fileURLWithPath: "/usr/bin/tar"),
                arguments: ["-xf", archive.path, "-C", directory.path]
            )
        }
    }

    /// Removes the Gatekeeper quarantine flag recursively (best effort).
    public static func removeQuarantine(_ url: URL) async {
        _ = try? await ProcessRunner.run(
            URL(fileURLWithPath: "/usr/bin/xattr"),
            arguments: ["-dr", "com.apple.quarantine", url.path]
        )
    }

    /// Mounts a `.dmg` read-only, runs `body` with the mount point and detaches afterwards.
    public static func withMountedDiskImage<T>(_ image: URL, _ body: (URL) async throws -> T) async throws -> T {
        let mountPoint = FileManager.default.temporaryDirectory
            .appendingPathComponent("blottle-dmg-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        try await ProcessRunner.check(
            URL(fileURLWithPath: "/usr/bin/hdiutil"),
            arguments: ["attach", "-nobrowse", "-readonly", "-noverify", "-mountpoint", mountPoint.path, image.path]
        )
        do {
            let value = try await body(mountPoint)
            await detach(mountPoint)
            return value
        } catch {
            await detach(mountPoint)
            throw error
        }
    }

    private static func detach(_ mountPoint: URL) async {
        _ = try? await ProcessRunner.run(
            URL(fileURLWithPath: "/usr/bin/hdiutil"),
            arguments: ["detach", mountPoint.path, "-force"]
        )
        try? FileManager.default.removeItem(at: mountPoint)
    }

    /// Finds the first directory (or file) with `name` under `root`, up to `maxDepth` levels deep.
    public static func find(named name: String, under root: URL, maxDepth: Int = 8) -> URL? {
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return nil }
        let rootDepth = root.standardizedFileURL.pathComponents.count
        for case let url as URL in enumerator {
            let depth = url.standardizedFileURL.pathComponents.count - rootDepth
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            if url.lastPathComponent == name {
                return url
            }
        }
        return nil
    }
}
