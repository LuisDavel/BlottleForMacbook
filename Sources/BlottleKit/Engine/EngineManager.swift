import Foundation

public enum InstallProgress: Sendable {
    case downloading(Double)
    case extracting
    case finishing

    public var description: String {
        switch self {
        case .downloading(let fraction): return "Baixando… \(Int(fraction * 100))%"
        case .extracting: return "Extraindo…"
        case .finishing: return "Finalizando…"
        }
    }
}

/// Metadata persisted next to each engine as `engine.json`.
struct EngineRecord: Codable {
    var id: String
    var name: String
    var version: String
    var flavor: EngineFlavor
    /// Absolute path of the Wine root, or a path relative to the engine folder.
    var rootPath: String
}

/// Installs, imports and lists Wine engines under `BlottlePaths.engines`.
public final class EngineManager {
    public static let recordFileName = "engine.json"

    public let directory: URL

    public init(directory: URL = BlottlePaths.engines) {
        self.directory = directory
    }

    // MARK: - Listing

    public func installed() -> [WineEngine] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries.compactMap { load(folder: $0) }.sorted { $0.name < $1.name }
    }

    public func engine(id: String) -> WineEngine? {
        load(folder: directory.appendingPathComponent(id, isDirectory: true))
    }

    public func load(folder: URL) -> WineEngine? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        let recordURL = folder.appendingPathComponent(Self.recordFileName)
        if let data = try? Data(contentsOf: recordURL),
           let record = try? JSONDecoder().decode(EngineRecord.self, from: data) {
            let root = record.rootPath.hasPrefix("/")
                ? URL(fileURLWithPath: record.rootPath, isDirectory: true)
                : folder.appendingPathComponent(record.rootPath, isDirectory: true)
            let engine = WineEngine(id: record.id, name: record.name, version: record.version, flavor: record.flavor, root: root)
            return engine.isValid ? engine : nil
        }
        // No record: maybe someone dropped a Wine folder in by hand.
        guard let root = WineEngine.locateRoot(in: folder) else { return nil }
        return WineEngine(
            id: folder.lastPathComponent,
            name: folder.lastPathComponent,
            version: "",
            flavor: WineEngine.guessFlavor(for: root),
            root: root
        )
    }

    // MARK: - Install from catalog

    public func install(
        _ entry: CatalogEntry,
        progress: @escaping (InstallProgress) -> Void = { _ in }
    ) async throws -> WineEngine {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let folder = directory.appendingPathComponent(entry.id, isDirectory: true)
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }

        let archive = try await Downloader.cached(entry.url, sha256: entry.sha256) { fraction in
            progress(.downloading(fraction))
        }

        progress(.extracting)
        let payload = folder.appendingPathComponent("payload", isDirectory: true)
        try await Archive.extract(archive, to: payload)

        progress(.finishing)
        guard let root = WineEngine.locateRoot(in: payload) else {
            try? FileManager.default.removeItem(at: folder)
            throw BlottleError.engineInvalid(payload.path)
        }
        await Archive.removeQuarantine(payload)
        var engine = WineEngine(id: entry.id, name: entry.name, version: entry.version, flavor: entry.flavor, root: root)
        let probed = await WineEngine.probeVersion(wineBinary: engine.wineBinary)
        if !probed.isEmpty { engine.version = probed }
        try save(engine, folder: folder)
        return engine
    }

    // MARK: - Import an existing Wine (CrossOver, GPTK, Gcenx .app in /Applications…)

    /// Registers a Wine that already lives somewhere else, via a symbolic link.
    public func importEngine(from source: URL, name: String? = nil, flavor: EngineFlavor? = nil) async throws -> WineEngine {
        guard let root = WineEngine.locateRoot(in: source) else {
            throw BlottleError.engineInvalid(source.path)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let resolvedFlavor = flavor ?? WineEngine.guessFlavor(for: root)
        let baseName = name ?? Self.suggestedName(for: source, flavor: resolvedFlavor)
        var id = Self.slug(baseName)
        var counter = 2
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(id).path) {
            id = Self.slug(baseName) + "-\(counter)"
            counter += 1
        }
        let folder = directory.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: folder.appendingPathComponent("wine"),
            withDestinationURL: root
        )
        var engine = WineEngine(id: id, name: baseName, version: "", flavor: resolvedFlavor, root: root)
        engine.version = await WineEngine.probeVersion(wineBinary: engine.wineBinary)
        try save(engine, folder: folder)
        return engine
    }

    public func remove(_ engine: WineEngine) throws {
        let folder = directory.appendingPathComponent(engine.id, isDirectory: true)
        guard FileManager.default.fileExists(atPath: folder.path) else {
            throw BlottleError.engineNotFound(engine.id)
        }
        try FileManager.default.removeItem(at: folder)
    }

    public func rename(_ engine: WineEngine, to name: String) throws {
        var updated = engine
        updated.name = name
        try save(updated, folder: directory.appendingPathComponent(engine.id, isDirectory: true))
    }

    func save(_ engine: WineEngine, folder: URL) throws {
        let folderPath = folder.standardizedFileURL.path
        let rootPath = engine.root.standardizedFileURL.path
        let relative: String
        if rootPath.hasPrefix(folderPath + "/") {
            relative = String(rootPath.dropFirst(folderPath.count + 1))
        } else {
            relative = rootPath
        }
        let record = EngineRecord(
            id: engine.id,
            name: engine.name,
            version: engine.version,
            flavor: engine.flavor,
            rootPath: relative
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: folder.appendingPathComponent(Self.recordFileName))
    }

    // MARK: - System candidates

    public struct Candidate: Hashable, Sendable {
        public let name: String
        public let url: URL
        public let flavor: EngineFlavor
    }

    /// Wine installations commonly found on a Mac (only those that exist are returned).
    public static func systemCandidates() -> [Candidate] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let known: [(String, String, EngineFlavor)] = [
            ("Wine Stable.app", "/Applications/Wine Stable.app", .wineStable),
            ("Wine Devel.app", "/Applications/Wine Devel.app", .wineDevel),
            ("Wine Staging.app", "/Applications/Wine Staging.app", .wineStaging),
            ("Wine Crossover.app", "/Applications/Wine Crossover.app", .crossover),
            ("CrossOver.app", "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver", .crossover),
            ("Game Porting Toolkit.app", "/Applications/Game Porting Toolkit.app", .gptk),
            ("WhiskyWine", "\(home)/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine", .whisky),
            ("Homebrew game-porting-toolkit", "/usr/local/opt/game-porting-toolkit", .gptk),
            ("Homebrew wine-stable", "/usr/local/opt/wine-stable", .wineStable),
        ]
        return known.compactMap { name, path, flavor in
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path), WineEngine.locateRoot(in: url) != nil else { return nil }
            return Candidate(name: name, url: url, flavor: flavor)
        }
    }

    static func suggestedName(for url: URL, flavor: EngineFlavor) -> String {
        let last = url.lastPathComponent
        if last.hasSuffix(".app") { return String(last.dropLast(4)) }
        if last.isEmpty || last == "/" { return flavor.displayName }
        return last
    }

    public static func slug(_ text: String) -> String {
        let lowered = text.lowercased()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-."))
        var result = ""
        var lastWasDash = false
        for scalar in lowered.unicodeScalars {
            if allowed.contains(scalar) {
                result.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash {
                result.append("-")
                lastWasDash = true
            }
        }
        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "engine" : trimmed
    }
}
