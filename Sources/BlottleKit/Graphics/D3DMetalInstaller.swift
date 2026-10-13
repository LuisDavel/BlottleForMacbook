import Foundation

/// Drops Apple's D3DMetal libraries (from the Game Porting Toolkit download)
/// into a GPTK-based Wine engine.
///
/// Apple's licence forbids redistributing these files, so the user downloads
/// the "Game Porting Toolkit" disk image from developer.apple.com and points
/// Blottle at it.
public enum D3DMetalInstaller {
    public static let appleDownloadPage = URL(string: "https://developer.apple.com/download/all/?q=Game%20Porting%20Toolkit")!

    public static func isInstalled(in engine: WineEngine) -> Bool {
        engine.hasD3DMetal
    }

    /// `source` can be the `.dmg`, the mounted volume, a `.app` or any folder containing `lib/external`.
    public static func install(from source: URL, into engine: WineEngine) async throws {
        guard engine.supportsD3DMetal else {
            throw BlottleError.notSupported(
                "D3DMetal só funciona com engines baseadas no Game Porting Toolkit (WhiskyWine, GPTK, CrossOver). A engine \(engine.name) é \(engine.flavor.displayName)."
            )
        }
        if source.pathExtension.lowercased() == "dmg" {
            try await Archive.withMountedDiskImage(source) { mountPoint in
                try copyLibraries(from: mountPoint, into: engine)
            }
        } else {
            try copyLibraries(from: source, into: engine)
        }
    }

    static func copyLibraries(from root: URL, into engine: WineEngine) throws {
        guard let framework = Archive.find(named: "D3DMetal.framework", under: root, maxDepth: 10) else {
            throw BlottleError.fileNotFound("D3DMetal.framework (dentro de \(root.path))")
        }
        let external = framework.deletingLastPathComponent()
        let fm = FileManager.default
        try fm.createDirectory(at: engine.externalLibDirectory, withIntermediateDirectories: true)
        for name in ["D3DMetal.framework", "libd3dshared.dylib"] {
            let from = external.appendingPathComponent(name)
            guard fm.fileExists(atPath: from.path) else { continue }
            let to = engine.externalLibDirectory.appendingPathComponent(name)
            if fm.fileExists(atPath: to.path) {
                let backup = engine.externalLibDirectory.appendingPathComponent(name + ".bak")
                try? fm.removeItem(at: backup)
                try fm.moveItem(at: to, to: backup)
            }
            try fm.copyItem(at: from, to: to)
        }
        guard engine.hasD3DMetal else {
            throw BlottleError.fileNotFound("D3DMetal.framework não foi copiado")
        }
    }
}
