import Foundation

/// Creates, lists, saves and deletes bottles under `BlottlePaths.bottles`.
public final class BottleStore {
    public let directory: URL

    public init(directory: URL = BlottlePaths.bottles) {
        self.directory = directory
    }

    public func list() -> [Bottle] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries.compactMap { try? load(at: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func load(at url: URL) throws -> Bottle {
        let metadata = url.appendingPathComponent(Bottle.metadataFileName)
        let data = try Data(contentsOf: metadata)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var bottle = try decoder.decode(Bottle.self, from: data)
        bottle.url = url
        return bottle
    }

    public func save(_ bottle: Bottle) throws {
        try FileManager.default.createDirectory(at: bottle.url, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(bottle).write(to: bottle.metadataURL, options: .atomic)
    }

    public func bottle(named name: String) -> Bottle? {
        list().first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    public func bottle(id: UUID) -> Bottle? {
        list().first { $0.id == id }
    }

    /// Finds a bottle by name, id or folder name.
    public func resolve(_ reference: String) -> Bottle? {
        if let uuid = UUID(uuidString: reference), let bottle = bottle(id: uuid) {
            return bottle
        }
        if let bottle = bottle(named: reference) {
            return bottle
        }
        let folder = directory.appendingPathComponent(reference, isDirectory: true)
        return try? load(at: folder)
    }

    /// Creates the folder + metadata and initialises the Wine prefix.
    public func create(
        name: String,
        engine: WineEngine,
        settings: BottleSettings = BottleSettings(),
        status: ((String) -> Void)? = nil
    ) async throws -> Bottle {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BlottleError.parseError("o nome da garrafa não pode ser vazio") }
        if bottle(named: trimmed) != nil {
            throw BlottleError.bottleAlreadyExists(trimmed)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var folderName = BlottleLog.sanitize(trimmed)
        var counter = 2
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(folderName).path) {
            folderName = BlottleLog.sanitize(trimmed) + "-\(counter)"
            counter += 1
        }
        let url = directory.appendingPathComponent(folderName, isDirectory: true)
        var bottle = Bottle(name: trimmed, engineID: engine.id, settings: settings, url: url)
        try save(bottle)

        let runner = WineRunner(engine: engine, bottle: bottle)
        status?("Inicializando prefixo Wine…")
        do {
            try await runner.initializePrefix()
            status?("Aplicando configurações…")
            try await applySettings(&bottle, engine: engine)
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        try save(bottle)
        return bottle
    }

    /// Pushes the registry-backed settings (Windows version, Retina, DPI) into the prefix.
    public func applySettings(_ bottle: inout Bottle, engine: WineEngine) async throws {
        let registry = WineRegistry(runner: WineRunner(engine: engine, bottle: bottle))
        try await registry.setWindowsVersion(bottle.settings.windowsVersion)
        try await registry.setRetinaMode(bottle.settings.retinaMode)
        try await registry.setDPI(bottle.settings.dpi)
        try save(bottle)
    }

    public func delete(_ bottle: Bottle) throws {
        guard FileManager.default.fileExists(atPath: bottle.metadataURL.path) else {
            throw BlottleError.bottleNotFound(bottle.name)
        }
        try FileManager.default.removeItem(at: bottle.url)
    }
}
