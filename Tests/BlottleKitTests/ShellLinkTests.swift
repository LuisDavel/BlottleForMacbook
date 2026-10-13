import XCTest
@testable import BlottleKit

final class ShellLinkTests: XCTestCase {
    func testParsesTargetArgumentsAndWorkingDirectory() throws {
        let data = TestSupport.makeShellLink(
            target: "C:\\Games\\Demo\\demo.exe",
            arguments: "-windowed -novid",
            workingDirectory: "C:\\Games\\Demo",
            description: "Demo Game"
        )
        let link = try ShellLink(data: data)
        XCTAssertEqual(link.targetPath, "C:\\Games\\Demo\\demo.exe")
        XCTAssertEqual(link.arguments, "-windowed -novid")
        XCTAssertEqual(link.workingDirectory, "C:\\Games\\Demo")
        XCTAssertEqual(link.linkDescription, "Demo Game")
    }

    func testParsesANSIStrings() throws {
        let data = TestSupport.makeShellLink(target: "C:\\app\\a.exe", arguments: "/x", unicode: false)
        let link = try ShellLink(data: data)
        XCTAssertEqual(link.targetPath, "C:\\app\\a.exe")
        XCTAssertEqual(link.arguments, "/x")
        XCTAssertNil(link.workingDirectory)
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try ShellLink(data: Data("not a shortcut".utf8)))
    }
}
