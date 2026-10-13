import XCTest
@testable import BlottleKit

final class ProgramScannerTests: XCTestCase {
    func testFindsStartMenuShortcutsAndProgramFiles() throws {
        let root = TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bottle = TestSupport.makeBottle(in: root)

        let exe = bottle.programFiles.appendingPathComponent("Demo/demo.exe")
        TestSupport.touch(exe)
        TestSupport.touch(bottle.programFiles.appendingPathComponent("Demo/unins000.exe"))
        TestSupport.touch(bottle.programFilesX86.appendingPathComponent("Tool/tool.exe"))

        let shortcut = bottle.driveC
            .appendingPathComponent("ProgramData/Microsoft/Windows/Start Menu/Programs/Demo/Demo Game.lnk")
        TestSupport.touch(shortcut, contents: TestSupport.makeShellLink(
            target: "C:\\Program Files\\Demo\\demo.exe",
            arguments: "-fullscreen",
            workingDirectory: "C:\\Program Files\\Demo"
        ))
        // A shortcut to a system binary must be ignored.
        TestSupport.touch(bottle.system32.appendingPathComponent("notepad.exe"))
        TestSupport.touch(
            bottle.driveC.appendingPathComponent("ProgramData/Microsoft/Windows/Start Menu/Programs/Notepad.lnk"),
            contents: TestSupport.makeShellLink(target: "C:\\windows\\system32\\notepad.exe")
        )

        let startMenu = ProgramScanner.startMenuPrograms(in: bottle)
        XCTAssertEqual(startMenu.count, 1)
        XCTAssertEqual(startMenu.first?.name, "Demo Game")
        XCTAssertEqual(startMenu.first?.path, exe.path)
        XCTAssertEqual(startMenu.first?.arguments, "-fullscreen")
        XCTAssertEqual(startMenu.first?.workingDirectory, bottle.programFiles.appendingPathComponent("Demo").path)

        let scanned = ProgramScanner.scannedPrograms(in: bottle)
        XCTAssertEqual(Set(scanned.map(\.name)), ["demo", "tool"])

        let all = ProgramScanner.allPrograms(in: bottle)
        XCTAssertEqual(all.count, 2, "demo.exe appears once even though it is both a shortcut and a scanned file")
        XCTAssertEqual(all.first?.source, .startMenu)
    }
}
