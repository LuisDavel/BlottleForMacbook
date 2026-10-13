import Foundation

/// Something that can be launched inside a bottle.
public struct Program: Identifiable, Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case generic
        case steam
    }

    public enum Source: String, Codable, CaseIterable, Sendable {
        /// Added by the user (drag & drop, "Run…" or the Steam installer).
        case pinned
        /// Discovered in the Windows Start Menu.
        case startMenu
        /// Discovered by scanning `Program Files`.
        case scanned
    }

    public var name: String
    /// Unix path of the executable inside the bottle (or anywhere on disk).
    public var path: String
    public var arguments: String
    public var workingDirectory: String?
    public var environment: [String: String]
    public var kind: Kind
    public var source: Source

    /// Case-insensitive, symlink-resolved path (so `/var/…` and `/private/var/…` are the same program).
    public var id: String { url.resolvingSymlinksInPath().path.lowercased() }
    public var url: URL { URL(fileURLWithPath: path) }

    public init(
        name: String,
        path: String,
        arguments: String = "",
        workingDirectory: String? = nil,
        environment: [String: String] = [:],
        kind: Kind = .generic,
        source: Source = .pinned
    ) {
        self.name = name
        self.path = path
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.kind = kind
        self.source = source
    }

    public var argumentList: [String] { ArgumentSplitter.split(arguments) }

    public var exists: Bool { FileManager.default.fileExists(atPath: path) }

    public static func name(forExecutable url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }
}
