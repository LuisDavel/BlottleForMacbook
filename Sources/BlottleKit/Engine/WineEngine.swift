import Foundation

/// Where a Wine build came from. This decides which graphics backends make sense.
public enum EngineFlavor: String, Codable, CaseIterable, Sendable {
    /// Plain WineHQ development build packaged by Gcenx.
    case wineDevel = "wine-devel"
    /// Wine Staging packaged by Gcenx.
    case wineStaging = "wine-staging"
    /// Wine Stable packaged by Gcenx.
    case wineStable = "wine-stable"
    /// Apple's Game Porting Toolkit Wine (D3DMetal-aware).
    case gptk
    /// Whisky's Wine (built from Apple's GPTK sources, D3DMetal-aware).
    case whisky
    /// CodeWeavers CrossOver's Wine.
    case crossover
    /// Anything imported by hand.
    case custom

    public var displayName: String {
        switch self {
        case .wineDevel: return "Wine Devel (Gcenx)"
        case .wineStaging: return "Wine Staging (Gcenx)"
        case .wineStable: return "Wine Stable (Gcenx)"
        case .gptk: return "Game Porting Toolkit (Apple)"
        case .whisky: return "WhiskyWine (GPTK)"
        case .crossover: return "CrossOver"
        case .custom: return "Personalizada"
        }
    }

    /// Only Wine builds patched by Apple know how to talk to D3DMetal.
    public var isGPTKBased: Bool {
        switch self {
        case .gptk, .whisky, .crossover: return true
        default: return false
        }
    }
}

/// A Wine installation: a directory with `bin/wine` (or `bin/wine64`) and `lib/`.
public struct WineEngine: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var name: String
    public var version: String
    public var flavor: EngineFlavor
    /// Directory that contains `bin/` and `lib/`.
    public var root: URL

    public init(id: String, name: String, version: String, flavor: EngineFlavor, root: URL) {
        self.id = id
        self.name = name
        self.version = version
        self.flavor = flavor
        self.root = root
    }

    public var binDirectory: URL { root.appendingPathComponent("bin", isDirectory: true) }
    public var libDirectory: URL { root.appendingPathComponent("lib", isDirectory: true) }
    public var externalLibDirectory: URL { libDirectory.appendingPathComponent("external", isDirectory: true) }
    public var unixLibDirectory: URL { libDirectory.appendingPathComponent("wine/x86_64-unix", isDirectory: true) }
    public var windowsLibDirectory: URL { libDirectory.appendingPathComponent("wine/x86_64-windows", isDirectory: true) }

    /// Newer Wine (WoW64 mode) ships only `wine`; older builds ship `wine64`.
    public var wineBinary: URL {
        Self.wineBinary(inBinDirectory: binDirectory) ?? binDirectory.appendingPathComponent("wine")
    }

    public var wineserverBinary: URL { binDirectory.appendingPathComponent("wineserver") }

    public var isValid: Bool { Self.wineBinary(inBinDirectory: binDirectory) != nil }

    public var hasD3DMetal: Bool {
        FileManager.default.fileExists(atPath: externalLibDirectory.appendingPathComponent("D3DMetal.framework").path)
    }

    /// The engine can use D3DMetal once the Apple libraries are dropped into `lib/external`.
    public var supportsD3DMetal: Bool {
        flavor.isGPTKBased || hasD3DMetal
    }

    public var displayVersion: String {
        version.isEmpty ? "versão desconhecida" : version
    }

    // MARK: - Discovery

    static func wineBinary(inBinDirectory bin: URL) -> URL? {
        for name in ["wine64", "wine"] {
            let candidate = bin.appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// Relative locations where a Wine root tends to hide inside app bundles.
    static let knownRootSubpaths = [
        "",
        "Contents/Resources/wine",
        "Contents/Resources",
        "Contents/SharedSupport/Wine",
        "Contents/SharedSupport/CrossOver",
        "Contents/SharedSupport/wine",
        "Libraries/Wine",
        "Wine",
        "wine",
        "usr",
    ]

    /// Finds the Wine root (the directory with `bin/wine`) at or below `url`.
    public static func locateRoot(in url: URL, maxDepth: Int = 5) -> URL? {
        for subpath in knownRootSubpaths {
            let candidate = subpath.isEmpty ? url : url.appendingPathComponent(subpath, isDirectory: true)
            if wineBinary(inBinDirectory: candidate.appendingPathComponent("bin", isDirectory: true)) != nil {
                return candidate
            }
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        let rootDepth = url.standardizedFileURL.pathComponents.count
        for case let entry as URL in enumerator {
            let depth = entry.standardizedFileURL.pathComponents.count - rootDepth
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            if entry.lastPathComponent == "bin", wineBinary(inBinDirectory: entry) != nil {
                return entry.deletingLastPathComponent()
            }
        }
        return nil
    }

    /// Guesses the flavor from the path of a Wine root.
    public static func guessFlavor(for root: URL) -> EngineFlavor {
        let path = root.path.lowercased()
        if path.contains("crossover") { return .crossover }
        if path.contains("game porting toolkit") || path.contains("gptk") || path.contains("game-porting-toolkit") { return .gptk }
        if path.contains("whisky") { return .whisky }
        if path.contains("staging") { return .wineStaging }
        if path.contains("devel") { return .wineDevel }
        if path.contains("stable") { return .wineStable }
        let external = root.appendingPathComponent("lib/external/D3DMetal.framework")
        if FileManager.default.fileExists(atPath: external.path) { return .gptk }
        return .custom
    }

    /// Runs `wine --version` and returns the trimmed output (e.g. `wine-11.18`).
    public static func probeVersion(wineBinary: URL) async -> String {
        guard let result = try? await ProcessRunner.run(wineBinary, arguments: ["--version"]) else { return "" }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n").first.map(String.init) ?? ""
    }
}
