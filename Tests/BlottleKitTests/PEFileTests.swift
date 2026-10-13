import XCTest
@testable import BlottleKit

final class PEFileTests: XCTestCase {
    func testParses64BitGUI() throws {
        let pe = try PEFile(data: TestSupport.makePE(machine: 0x8664, magic: 0x20B, subsystem: 2))
        XCTAssertEqual(pe.machine, .amd64)
        XCTAssertTrue(pe.is64Bit)
        XCTAssertEqual(pe.subsystem, .windowsGUI)
    }

    func testParses32BitConsole() throws {
        let pe = try PEFile(data: TestSupport.makePE(machine: 0x014C, magic: 0x10B, subsystem: 3))
        XCTAssertEqual(pe.machine, .i386)
        XCTAssertFalse(pe.is64Bit)
        XCTAssertEqual(pe.subsystem, .windowsConsole)
    }

    func testRejectsNonPE() {
        XCTAssertThrowsError(try PEFile(data: Data(repeating: 0, count: 128)))
    }
}
