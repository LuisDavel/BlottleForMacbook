import Foundation

/// Creates, lists, saves and deletes bottles under `BlottlePaths.bottles`, plus
/// bottles that live elsewhere (e.g. on an external SSD) and are tracked in a
/// small registry file (`ExternalBottles.json`).
public final class BottleStore {
    public static let registryFileName = "ExternalBottles.json"

    public let directory: URL
    /// JSON array of absolute paths of bottles outside `directory`.
    public let registryFile: URL

    public init(directory: URL = BlottlePaths.bottles, registryFile: URL? = nil) {
        self.directory = directory
        self.registryFile = registryFile ?? BlottlePaths.root.appendingPathComponent(Self.registryFileName)
    }

    public func list() -> [Bottle] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        var seen = Set<String>()
        return (entries + externalLocations())
            .compactMap { try? load(at: $0) }
            .filter { seen.insert($0.url.standardizedFileURL.path).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - External locations

    /// Registered bottle folders outside `directory`. Missing folders (disk unplugged)
    /// stay registered and simply don't show up in `list()`.
    public func externalLocations() -> [URL] {
        guard let data = try? Data(contentsOf: registryFile),
              let paths = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return paths.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private func writeExternalLocations(_ urls: [URL]) throws {
        try FileManager.default.createDirectory(at: registryFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(urls.map(\.standardizedFileURL.path)).write(to: registryFile, options: .atomic)
    }

    public func register(external url: URL) throws {
        var urls = externalLocations()
        let path = url.standardizedFileURL.path
        guard !urls.contains(where: { $0.standardizedFileURL.path == path }) else { return }
        urls.append(url)
        try writeExternalLocations(urls)
    }

    public func unregister(external url: URL) throws {
        let path = url.standardizedFileURL.path
        let urls = externalLocations().filter { $0.standardizedFileURL.path != path }
        try writeExternalLocations(urls)
    }

    private func isInsideDefaultDirectory(_ url: URL) -> Bool {
        url.standardizedFileURL.deletingLastPathComponent().path == directory.standardizedFileURL.path
    }

    /// Checks that `location` can hold a Wine prefix: it must exist and the volume must
    /// support symbolic links (`dosdevices/c:` is a symlink). exFAT/FAT32 don't.
    public static func validateLocation(_ location: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: location.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw BlottleError.fileNotFound(location.path)
        }
        let values = try location.resourceValues(forKeys: [.volumeSupportsSymbolicLinksKey, .volumeNameKey, .volumeLocalizedFormatDescriptionKey])
        if values.volumeSupportsSymbolicLinks == false {
            let volume = values.volumeName ?? location.path
            let format = values.volumeLocalizedFormatDescription.map { " (\($0))" } ?? ""
            throw BlottleError.notSupported("o volume \"\(volume)\"\(format) não suporta links simbólicos, que o Wine exige. Formate o disco como APFS (Utilitário de Disco) e tente de novo.")
        }
        guard FileManager.default.isWritableFile(atPath: location.path) else {
            throw BlottleError.notSupported("sem permissão de escrita em \(location.path)")
        }
    }

    /// Picks a free folder for a new bottle, inside `location` (validated) or the default
    /// directory, and registers it when external. The folder itself is not created.
    public func allocateFolder(name: String, location: URL?) throws -> URL {
        let parent: URL
        if let location, !isInsideDefaultDirectory(location.appendingPathComponent("x")) {
            try Self.validateLocation(location)
            parent = location
        } else {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            parent = directory
        }
        var folderName = BlottleLog.sanitize(name)
        var counter = 2
        while FileManager.default.fileExists(atPath: parent.appendingPathComponent(folderName).path) {
            folderName = BlottleLog.sanitize(name) + "-\(counter)"
            counter += 1
        }
        let url = parent.appendingPathComponent(folderName, isDirectory: true)
        if !isInsideDefaultDirectory(url) {
            try register(external: url)
        }
        return url
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
    /// `location` is an optional parent folder (e.g. on an external disk); `nil` uses the default.
    public func create(
        name: String,
        engine: WineEngine,
        settings: BottleSettings = BottleSettings(),
        location: URL? = nil,
        status: ((String) -> Void)? = nil
    ) async throws -> Bottle {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BlottleError.parseError("o nome da garrafa não pode ser vazio") }
        if bottle(named: trimmed) != nil {
            throw BlottleError.bottleAlreadyExists(trimmed)
        }
        let url = try allocateFolder(name: trimmed, location: location)
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
            try? unregister(external: url)
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
        try? unregister(external: bottle.url)
    }
}
