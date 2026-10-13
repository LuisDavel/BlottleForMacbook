import Foundation

/// Runs Wine commands inside a bottle with the right environment.
public struct WineRunner {
    public let engine: WineEngine
    public let bottle: Bottle

    public init(engine: WineEngine, bottle: Bottle) {
        self.engine = engine
        self.bottle = bottle
    }

    /// Full environment for a Wine process: inherits the user's shell environment,
    /// then layers the prefix, engine and bottle settings on top.
    public func environment(extra: [String: String] = [:]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = bottle.url.path
        env["WINEDEBUG"] = "fixme-all"
        env["GST_DEBUG"] = "1"
        // Wine's wrapper scripts and winetricks look up tools on PATH.
        let basePath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = [engine.binDirectory.path, "/opt/homebrew/bin", "/usr/local/bin", basePath].joined(separator: ":")
        env.merge(bottle.settings.environmentVariables()) { _, new in new }
        env.merge(extra) { _, new in new }
        return env
    }

    // MARK: - Foreground commands

    @discardableResult
    public func run(
        _ arguments: [String],
        workingDirectory: URL? = nil,
        extraEnvironment: [String: String] = [:],
        logName: String? = nil
    ) async throws -> ProcessResult {
        let log = try logName.map { try BlottleLog.open(bottle: bottle.name, name: $0) }
        defer { try? log?.handle.close() }
        return try await ProcessRunner.run(
            engine.wineBinary,
            arguments: arguments,
            environment: environment(extra: extraEnvironment),
            currentDirectory: workingDirectory,
            log: log?.handle
        )
    }

    @discardableResult
    public func check(
        _ arguments: [String],
        workingDirectory: URL? = nil,
        extraEnvironment: [String: String] = [:],
        logName: String? = nil
    ) async throws -> ProcessResult {
        let result = try await run(
            arguments,
            workingDirectory: workingDirectory,
            extraEnvironment: extraEnvironment,
            logName: logName
        )
        guard result.succeeded else {
            throw BlottleError.processFailed(
                command: "wine " + arguments.joined(separator: " "),
                exitCode: result.exitCode,
                output: result.output
            )
        }
        return result
    }

    @discardableResult
    public func wineserver(_ arguments: [String]) async throws -> ProcessResult {
        try await ProcessRunner.run(engine.wineserverBinary, arguments: arguments, environment: environment())
    }

    // MARK: - Background programs

    /// Starts a program and returns immediately. Output is written to a log file.
    public func launch(
        _ arguments: [String],
        workingDirectory: URL? = nil,
        extraEnvironment: [String: String] = [:],
        logName: String,
        onExit: ((Int32) -> Void)? = nil
    ) throws -> LaunchedProcess {
        let log = try BlottleLog.open(bottle: bottle.name, name: logName)
        let header = "[Blottle] \(Date()) wine \(arguments.joined(separator: " "))\n"
        log.handle.write(Data(header.utf8))
        let process = try ProcessRunner.launch(
            engine.wineBinary,
            arguments: arguments,
            environment: environment(extra: extraEnvironment),
            currentDirectory: workingDirectory,
            log: log.handle,
            onExit: { code in
                try? log.handle.close()
                onExit?(code)
            }
        )
        return LaunchedProcess(process: process, logURL: log.url)
    }

    // MARK: - Prefix lifecycle

    /// `wineboot --init` creates `drive_c`, the registry and the fake Windows tree.
    public func initializePrefix() async throws {
        try FileManager.default.createDirectory(at: bottle.url, withIntermediateDirectories: true)
        try await check(["wineboot", "--init"], logName: "wineboot")
        try await waitForWineserver()
    }

    /// Re-runs the prefix update (useful after switching engines).
    public func updatePrefix() async throws {
        try await check(["wineboot", "--update"], logName: "wineboot")
        try await waitForWineserver()
    }

    public func waitForWineserver() async throws {
        _ = try await wineserver(["-w"])
    }

    /// Kills every process in the bottle.
    public func shutdown() async throws {
        _ = try await wineserver(["-k"])
    }

    // MARK: - Standard tools

    public func openWinecfg() throws -> LaunchedProcess { try launch(["winecfg"], logName: "winecfg") }
    public func openRegedit() throws -> LaunchedProcess { try launch(["regedit"], logName: "regedit") }
    public func openTaskManager() throws -> LaunchedProcess { try launch(["taskmgr"], logName: "taskmgr") }
    public func openControlPanel() throws -> LaunchedProcess { try launch(["control"], logName: "control") }
    public func openExplorer() throws -> LaunchedProcess { try launch(["explorer"], logName: "explorer") }
    public func openCommandPrompt() throws -> LaunchedProcess { try launch(["wineconsole", "cmd"], logName: "cmd") }
}

/// Handle to a program started inside a bottle.
public final class LaunchedProcess {
    public let process: Process
    public let logURL: URL

    init(process: Process, logURL: URL) {
        self.process = process
        self.logURL = logURL
    }

    public var isRunning: Bool { process.isRunning }
    public var processIdentifier: Int32 { process.processIdentifier }

    public func terminate() {
        if process.isRunning { process.terminate() }
    }
}
