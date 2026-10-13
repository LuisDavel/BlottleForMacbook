import Foundation
import CryptoKit

/// Downloads files with progress reporting and optional SHA-256 verification.
public enum Downloader {
    public static func download(
        _ url: URL,
        to destination: URL,
        sha256: String? = nil,
        progress: ((Double) -> Void)? = nil
    ) async throws {
        let delegate = DownloadProgressDelegate(progress: progress)
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 120)
        let (temporaryURL, response) = try await URLSession.shared.download(for: request, delegate: delegate)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw BlottleError.downloadFailed("\(url.absoluteString) respondeu HTTP \(http.statusCode)")
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)

        if let sha256 {
            let actual = try fileSHA256(destination)
            guard actual.lowercased() == sha256.lowercased() else {
                try? FileManager.default.removeItem(at: destination)
                throw BlottleError.checksumMismatch(expected: sha256, actual: actual)
            }
        }
        progress?(1.0)
    }

    /// Downloads into the cache directory, reusing a previous download when the
    /// file is already present (and matches the checksum, when one is given).
    public static func cached(
        _ url: URL,
        fileName: String? = nil,
        sha256: String? = nil,
        progress: ((Double) -> Void)? = nil
    ) async throws -> URL {
        let name = fileName ?? url.lastPathComponent
        let destination = BlottlePaths.cache.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: destination.path) {
            if let sha256, let actual = try? fileSHA256(destination), actual.lowercased() != sha256.lowercased() {
                try? FileManager.default.removeItem(at: destination)
            } else {
                progress?(1.0)
                return destination
            }
        }
        try await download(url, to: destination, sha256: sha256, progress: progress)
        return destination
    }

    public static func fileSHA256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 1 << 20)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    private let progress: ((Double) -> Void)?

    init(progress: ((Double) -> Void)?) {
        self.progress = progress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The async `download(for:delegate:)` API hands the file back to the caller.
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }
}
