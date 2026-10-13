import Foundation

/// Launches Windows files of any kind inside a bottle.
public enum ProgramLauncher {
    /// Translates a file into the `wine …` argument list that opens it.
    public static func wineArguments(for file: URL, arguments: [String]) -> [String] {
        switch file.pathExtension.lowercased() {
        case "msi":
            return ["msiexec", "/i", file.path] + arguments
        case "bat", "cmd":
            return ["cmd", "/c", file.path] + arguments
        case "reg":
            return ["regedit", "/S", file.path]
        case "lnk":
            return ["start", "/unix", file.path] + arguments
        default:
            return [file.path] + arguments
        }
    }

    public static func launch(
        file: URL,
        arguments: [String] = [],
        workingDirectory: URL? = nil,
        environment: [String: String] = [:],
        in bottle: Bottle,
        engine: WineEngine,
        onExit: ((Int32) -> Void)? = nil
    ) throws -> LaunchedProcess {
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw BlottleError.fileNotFound(file.path)
        }
        let runner = WineRunner(engine: engine, bottle: bottle)
        let directory = workingDirectory ?? file.deletingLastPathComponent()
        return try runner.launch(
            wineArguments(for: file, arguments: arguments),
            workingDirectory: directory,
            extraEnvironment: environment,
            logName: Program.name(forExecutable: file),
            onExit: onExit
        )
    }

    public static func launch(
        _ program: Program,
        in bottle: Bottle,
        engine: WineEngine,
        onExit: ((Int32) -> Void)? = nil
    ) throws -> LaunchedProcess {
        if program.kind == .steam, bottle.settings.steamWebHelperFix {
            _ = try? SteamInstaller.applyWebHelperWrapper(to: bottle)
        }
        let workingDirectory = program.workingDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) }
        return try launch(
            file: program.url,
            arguments: program.argumentList,
            workingDirectory: workingDirectory,
            environment: program.environment,
            in: bottle,
            engine: engine,
            onExit: onExit
        )
    }
}
