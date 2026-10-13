import XCTest
@testable import BlottleKit

final class BlottleLogTests: XCTestCase {
    private func makeLogs(_ count: Int, in dir: URL) throws {
        let fm = FileManager.default
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for i in 0..<count {
            let url = dir.appendingPathComponent("run-\(i).log")
            fm.createFile(atPath: url.path, contents: Data())
            try fm.setAttributes([.modificationDate: base.addingTimeInterval(Double(i) * 60)], ofItemAtPath: url.path)
        }
    }

    func testPruneRemovesOldestLogs() throws {
        let dir = TestSupport.temporaryDirectory()
        try makeLogs(45, in: dir)
        BlottleLog.prune(directory: dir, keep: 40)
        let names = Set(try FileManager.default.contentsOfDirectory(atPath: dir.path))
        XCTAssertEqual(names.count, 40)
        for i in 0..<5 { XCTAssertFalse(names.contains("run-\(i).log")) }
        for i in 5..<45 { XCTAssertTrue(names.contains("run-\(i).log")) }
    }

    func testPruneLeavesNonLogFilesUntouched() throws {
        let dir = TestSupport.temporaryDirectory()
        let fm = FileManager.default
        try makeLogs(5, in: dir)
        let other = dir.appendingPathComponent("notes.txt")
        fm.createFile(atPath: other.path, contents: Data())
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: other.path)
        BlottleLog.prune(directory: dir, keep: 2)
        XCTAssertTrue(fm.fileExists(atPath: other.path))
        let logs = try fm.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".log") }
        XCTAssertEqual(Set(logs), ["run-3.log", "run-4.log"])
    }
}
