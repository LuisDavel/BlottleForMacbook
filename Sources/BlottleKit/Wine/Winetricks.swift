import Foundation

/// Runs the community `winetricks` script against a bottle.
public enum Winetricks {
    public static let scriptURL = URL(string: "https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks")!

    public static var scriptLocation: URL {
        BlottlePaths.cache.appendingPathComponent("winetricks")
    }

    /// Verbs most people end up needing for games and launchers.
    public static let popularVerbs: [(verb: String, description: String)] = [
        ("corefonts", "Fontes básicas da Microsoft (Arial, Times…)"),
        ("tahoma", "Fonte Tahoma"),
        ("vcrun2022", "Visual C++ 2015-2022 Redistributable"),
        ("vcrun2019", "Visual C++ 2015-2019 Redistributable"),
        ("vcrun2013", "Visual C++ 2013 Redistributable"),
        ("vcrun2010", "Visual C++ 2010 Redistributable"),
        ("dotnet48", ".NET Framework 4.8"),
        ("d3dcompiler_47", "Compilador HLSL d3dcompiler_47"),
        ("dxvk", "DXVK (versão do winetricks, pode ser incompatível com macOS)"),
        ("xact", "XACT / X3DAudio"),
        ("xinput", "XInput (controles)"),
        ("physx", "NVIDIA PhysX"),
        ("mfc140", "MFC 14"),
    ]

    public static func ensureScript(forceUpdate: Bool = false) async throws -> URL {
        let location = scriptLocation
        if forceUpdate || !FileManager.default.fileExists(atPath: location.path) {
            try await Downloader.download(scriptURL, to: location)
            _ = try? await ProcessRunner.run(URL(fileURLWithPath: "/bin/chmod"), arguments: ["+x", location.path])
        }
        return location
    }

    public static func missingDependencies() -> [String] {
        ["cabextract"].filter { ProcessRunner.which($0) == nil }
    }

    @discardableResult
    public static func run(
        verbs: [String],
        runner: WineRunner,
        unattended: Bool = true,
        forceUpdate: Bool = false
    ) async throws -> ProcessResult {
        let missing = missingDependencies()
        if !missing.isEmpty {
            throw BlottleError.missingDependency(
                "\(missing.joined(separator: ", ")) — instale com `brew install \(missing.joined(separator: " "))`"
            )
        }
        let script = try await ensureScript(forceUpdate: forceUpdate)
        var env = runner.environment()
        env["WINE"] = runner.engine.wineBinary.path
        env["WINESERVER"] = runner.engine.wineserverBinary.path
        env["WINETRICKS_LATEST_VERSION_CHECK"] = "disabled"
        // The 64-bit-only Wine in GPTK confuses winetricks' arch detection.
        if !runner.bottle.hasWOW64 {
            env["WINEARCH"] = "win64"
        }
        var arguments = [script.path]
        if unattended { arguments.append("-q") }
        arguments.append(contentsOf: verbs)
        let log = try BlottleLog.open(bottle: runner.bottle.name, name: "winetricks")
        defer { try? log.handle.close() }
        return try await ProcessRunner.run(
            URL(fileURLWithPath: "/bin/bash"),
            arguments: arguments,
            environment: env,
            log: log.handle
        )
    }
}
