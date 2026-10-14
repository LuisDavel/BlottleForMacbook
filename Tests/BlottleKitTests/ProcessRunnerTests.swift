import XCTest
@testable import BlottleKit

final class ProcessRunnerTests: XCTestCase {
    private let sleepBinary = URL(fileURLWithPath: "/bin/sleep")

    func testTimeoutTerminatesProcess() async {
        let start = Date()
        do {
            _ = try await ProcessRunner.run(sleepBinary, arguments: ["30"], timeout: 1)
            XCTFail("expected timedOut")
        } catch let error as BlottleError {
            guard case .timedOut(let command, let seconds) = error else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertEqual(command, "sleep 30")
            XCTAssertEqual(seconds, 1)
        } catch {
            XCTFail("unexpected error \(error)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testCancellationTerminatesProcess() async {
        let task = Task { try await ProcessRunner.run(sleepBinary, arguments: ["30"]) }
        try? await Task.sleep(for: .milliseconds(300))
        let start = Date()
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected CancellationError")
        } catch is CancellationError {
            // ok
        } catch {
            XCTFail("unexpected error \(error)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testNormalExitStillWorks() async throws {
        let result = try await ProcessRunner.run(URL(fileURLWithPath: "/bin/echo"), arguments: ["hi"], timeout: 10)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.output.trimmingCharacters(in: .whitespacesAndNewlines), "hi")
    }
}
