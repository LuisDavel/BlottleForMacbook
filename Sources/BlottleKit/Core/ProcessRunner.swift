import Foundation

public struct ProcessResult: Sendable {
    public let exitCode: Int32
    public let output: String

    public var succeeded: Bool { exitCode == 0 }

    public init(exitCode: Int32, output: String) {
        self.exitCode = exitCode
        self.output = output
    }
}

/// Thread-safe accumulator for process output that can also mirror
/// everything into a log file.
final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private let log: FileHandle?

    init(log: FileHandle?) {
        self.log = log
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        buffer.append(data)
        lock.unlock()
        log?.write(data)
    }

    var string: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: buffer, as: UTF8.self)
    }
}

/// Coordinates the single resumption of `ProcessRunner.run` between normal
/// exit, timeout and task cancellation.
private final class RunState: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private let reader: FileHandle
    private var continuation: CheckedContinuation<ProcessResult, Error>?
    private var started = false
    private var done = false
    private var pendingError: Error?

    init(process: Process, reader: FileHandle) {
        self.process = process
        self.reader = reader
    }

    /// Launches the process unless the run was already cancelled.
    func start(_ continuation: CheckedContinuation<ProcessResult, Error>) {
        lock.lock()
        if let pendingError {
            done = true
            lock.unlock()
            reader.readabilityHandler = nil
            continuation.resume(throwing: pendingError)
            return
        }
        self.continuation = continuation
        do {
            try process.run()
            started = true
            lock.unlock()
        } catch {
            done = true
            self.continuation = nil
            lock.unlock()
            reader.readabilityHandler = nil
            continuation.resume(throwing: error)
        }
    }

    /// Resumes with `result` if nothing else did first.
    func finish(_ result: Result<ProcessResult, Error>) {
        lock.lock()
        guard !done, let continuation else {
            lock.unlock()
            return
        }
        done = true
        self.continuation = nil
        lock.unlock()
        reader.readabilityHandler = nil
        continuation.resume(with: result)
    }

    /// Terminates the process and resumes right away with `error`, without
    /// waiting for the process to actually die (it may be stuck on I/O).
    func stop(with error: Error) {
        lock.lock()
        guard !done else {
            lock.unlock()
            return
        }
        guard started else {
            // Not launched yet: `start` will see this and bail out.
            pendingError = error
            lock.unlock()
            return
        }
        lock.unlock()
        Self.terminate(process)
        finish(.failure(error))
    }

    /// SIGTERM, then SIGKILL after 2s if the process is still alive.
    static func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            if process.isRunning {
                kill(pid, SIGKILL)
            }
        }
    }
}

/// Small wrapper over `Foundation.Process`.
///
/// Wine spawns a `wineserver` daemon that inherits our pipes and may keep them
/// open long after the foreground command exited, so `run` never blocks on
/// end-of-file: it resolves as soon as the process terminates.
public enum ProcessRunner {
    /// Runs a command and waits for it to exit, capturing stdout+stderr.
    ///
    /// - Parameter timeout: when set, the process is terminated (SIGTERM, then
    ///   SIGKILL after 2s) once it runs longer than this and
    ///   `BlottleError.timedOut` is thrown.
    ///
    /// Cancelling the calling task terminates the process the same way and
    /// throws `CancellationError`.
    public static func run(
        _ executable: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        log: FileHandle? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }
        if let currentDirectory {
            process.currentDirectoryURL = currentDirectory
        }
        process.standardInput = FileHandle.nullDevice

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let collector = OutputCollector(log: log)
        let reader = pipe.fileHandleForReading
        reader.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            collector.append(data)
        }

        let command = ([executable.lastPathComponent] + arguments).joined(separator: " ")
        let run = RunState(process: process, reader: reader)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ProcessResult, Error>) in
                process.terminationHandler = { finished in
                    // Give the reader a moment to drain what is already buffered,
                    // then stop listening: a lingering wineserver may hold the
                    // write end open indefinitely.
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) {
                        run.finish(.success(ProcessResult(
                            exitCode: finished.terminationStatus,
                            output: collector.string
                        )))
                    }
                }
                run.start(continuation)
                if let timeout {
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                        run.stop(with: BlottleError.timedOut(command: command, seconds: timeout))
                    }
                }
            }
        } onCancel: {
            run.stop(with: CancellationError())
        }
    }

    /// Runs a command and throws `BlottleError.processFailed` on a non-zero exit.
    @discardableResult
    public static func check(
        _ executable: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        log: FileHandle? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> ProcessResult {
        let result = try await run(
            executable,
            arguments: arguments,
            environment: environment,
            currentDirectory: currentDirectory,
            log: log,
            timeout: timeout
        )
        guard result.succeeded else {
            let command = ([executable.lastPathComponent] + arguments).joined(separator: " ")
            throw BlottleError.processFailed(command: command, exitCode: result.exitCode, output: result.output)
        }
        return result
    }

    /// Starts a long-running process (a game, Steam, winecfg…) without waiting.
    /// Output goes straight to `log` so there is no pipe to deadlock on.
    public static func launch(
        _ executable: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        log: FileHandle? = nil,
        onExit: ((Int32) -> Void)? = nil
    ) throws -> Process {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }
        if let currentDirectory {
            process.currentDirectoryURL = currentDirectory
        }
        process.standardInput = FileHandle.nullDevice
        if let log {
            process.standardOutput = log
            process.standardError = log
        } else {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }
        if let onExit {
            process.terminationHandler = { finished in
                onExit(finished.terminationStatus)
            }
        }
        try process.run()
        return process
    }

    /// Convenience for `/usr/bin/env`-style lookups of system tools.
    public static func which(_ tool: String) -> URL? {
        let searchPath = [
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
        ]
        for directory in searchPath {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(tool)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}
