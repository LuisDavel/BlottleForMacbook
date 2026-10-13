import Foundation

/// A Wine prefix plus Blottle's metadata (`Blottle.json` inside it).
public struct Bottle: Identifiable, Hashable, Codable, Sendable {
    public static let metadataFileName = "Blottle.json"

    public var id: UUID
    public var name: String
    public var engineID: String
    public var settings: BottleSettings
    public var programs: [Program]
    public var createdAt: Date
    /// Directory of the prefix (`WINEPREFIX`). Not persisted: derived from where the metadata lives.
    public var url: URL

    enum CodingKeys: String, CodingKey {
        case id, name, engineID, settings, programs, createdAt
    }

    public init(
        id: UUID = UUID(),
        name: String,
        engineID: String,
        settings: BottleSettings = BottleSettings(),
        programs: [Program] = [],
        createdAt: Date = Date(),
        url: URL
    ) {
        self.id = id
        self.name = name
        self.engineID = engineID
        self.settings = settings
        self.programs = programs
        self.createdAt = createdAt
        self.url = url
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        engineID = try container.decode(String.self, forKey: .engineID)
        settings = try container.decodeIfPresent(BottleSettings.self, forKey: .settings) ?? BottleSettings()
        programs = try container.decodeIfPresent([Program].self, forKey: .programs) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        url = URL(fileURLWithPath: "/")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(engineID, forKey: .engineID)
        try container.encode(settings, forKey: .settings)
        try container.encode(programs, forKey: .programs)
        try container.encode(createdAt, forKey: .createdAt)
    }

    // MARK: - Layout

    public var metadataURL: URL { url.appendingPathComponent(Self.metadataFileName) }
    public var driveC: URL { url.appendingPathComponent("drive_c", isDirectory: true) }
    public var dosDevices: URL { url.appendingPathComponent("dosdevices", isDirectory: true) }
    public var windowsDirectory: URL { driveC.appendingPathComponent("windows", isDirectory: true) }
    public var system32: URL { windowsDirectory.appendingPathComponent("system32", isDirectory: true) }
    public var sysWOW64: URL { windowsDirectory.appendingPathComponent("syswow64", isDirectory: true) }
    public var programFiles: URL { driveC.appendingPathComponent("Program Files", isDirectory: true) }
    public var programFilesX86: URL { driveC.appendingPathComponent("Program Files (x86)", isDirectory: true) }
    public var usersDirectory: URL { driveC.appendingPathComponent("users", isDirectory: true) }

    /// Wine names the user folder after the macOS user name.
    public var userDirectory: URL {
        usersDirectory.appendingPathComponent(NSUserName(), isDirectory: true)
    }

    /// True once `wineboot` has populated the prefix.
    public var isInitialized: Bool {
        FileManager.default.fileExists(atPath: system32.path)
    }

    public var hasWOW64: Bool {
        FileManager.default.fileExists(atPath: sysWOW64.path)
    }

    public mutating func pin(_ program: Program) {
        programs.removeAll { $0.id == program.id }
        programs.append(program)
    }

    public mutating func unpin(_ program: Program) {
        programs.removeAll { $0.id == program.id }
    }
}
