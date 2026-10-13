import Foundation

public enum RegistryType: String, Sendable {
    case string = "REG_SZ"
    case dword = "REG_DWORD"
    case binary = "REG_BINARY"
    case expandString = "REG_EXPAND_SZ"
}

/// Thin wrapper around `wine reg` and `winecfg`.
public struct WineRegistry {
    public let runner: WineRunner

    public init(runner: WineRunner) {
        self.runner = runner
    }

    public func add(key: String, name: String, type: RegistryType, value: String) async throws {
        try await runner.check(["reg", "add", key, "/v", name, "/t", type.rawValue, "/d", value, "/f"])
    }

    public func delete(key: String, name: String) async throws {
        _ = try await runner.run(["reg", "delete", key, "/v", name, "/f"])
    }

    /// Returns the value's data, or nil when it does not exist.
    public func query(key: String, name: String) async throws -> String? {
        let result = try await runner.run(["reg", "query", key, "/v", name])
        guard result.succeeded else { return nil }
        return Self.parseQueryOutput(result.output, name: name)
    }

    /// Parses `reg query` output, e.g. `    RetinaMode    REG_SZ    Y`.
    public static func parseQueryOutput(_ output: String, name: String) -> String? {
        for line in output.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 3, parts[0].caseInsensitiveCompare(name) == .orderedSame else { continue }
            return parts.dropFirst(2).joined(separator: " ")
        }
        return nil
    }

    public func setWindowsVersion(_ version: WindowsVersion) async throws {
        try await runner.check(["winecfg", "-v", version.rawValue])
    }

    public func setRetinaMode(_ enabled: Bool) async throws {
        try await add(key: "HKCU\\Software\\Wine\\Mac Driver", name: "RetinaMode", type: .string, value: enabled ? "Y" : "N")
    }

    public func setDPI(_ dpi: Int) async throws {
        let clamped = max(72, min(dpi, 480))
        try await add(key: "HKCU\\Control Panel\\Desktop", name: "LogPixels", type: .dword, value: "\(clamped)")
    }

    /// Lets programs that misbehave with Wine's Mac driver fall back to X11 (needs XQuartz).
    public func setGraphicsDriver(_ driver: String) async throws {
        try await add(key: "HKCU\\Software\\Wine\\Drivers", name: "Graphics", type: .string, value: driver)
    }
}
