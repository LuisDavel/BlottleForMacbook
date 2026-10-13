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

/// Small wrapper over `Foundation.Process`.
///
/// Wine spawns a `wineserver` daemon that inherits our pipes and may keep them
/// open long after the foreground command exited, so `run` never blocks on
/// end-of-file: it resolves as soon as the process terminates.
public enum ProcessRunner {
    /// Runs a command and waits for it to exit, capturing stdout+stderr.
    public static func run(
        _ executable: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        log: FileHandle? = nil
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

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finished in
                // Give the reader a moment to drain what is already buffered,
                // then stop listening: a lingering wineserver may hold the
                // write end open indefinitely.
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) {
                    reader.readabilityHandler = nil
                    continuation.resume(returning: ProcessResult(
                        exitCode: finished.terminationStatus,
                        output: collector.string
                    ))
                }
            }
            do {
                try process.run()
            } catch {
                reader.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }

    /// Runs a command and throws `BlottleError.processFailed` on a non-zero exit.
    @discardableResult
    public static func check(
        _ executable: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        log: FileHandle? = nil
    ) async throws -> ProcessResult {
        let result = try await run(
            executable,
            arguments: arguments,
            environment: environment,
            currentDirectory: currentDirectory,
            log: log
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
