import XCTest
@testable import BlottleKit

final class SteamInstallerTests: XCTestCase {
    func testProgramUsesPresetArguments() {
        let bottle = Bottle(name: "b", engineID: "e", url: URL(fileURLWithPath: "/tmp/b"))
        var options = SteamOptions()
        options.preset = .webHelperWrapper
        options.extraArguments = ["-silent"]
        let program = SteamInstaller.program(for: bottle, options: options)
        XCTAssertEqual(program.kind, .steam)
        XCTAssertEqual(program.path, "/tmp/b/drive_c/Program Files (x86)/Steam/steam.exe")
        XCTAssertEqual(program.argumentList, ["-noverifyfiles", "-silent"])

        options.preset = .cefFlags
        XCTAssertEqual(SteamInstaller.program(for: bottle, options: options).argumentList.first, "-allosarches")
    }

    func testWrapperDeploymentKeepsOriginal() throws {
        let root = TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bottle = TestSupport.makeBottle(in: root)

        let cef = SteamInstaller.steamDirectory(in: bottle).appendingPathComponent("bin/cef/cef.win7x64")
        let helper = cef.appendingPathComponent("steamwebhelper.exe")
        TestSupport.touch(helper, contents: Data("ORIGINAL".utf8))

        let wrappers = root.appendingPathComponent("wrappers", isDirectory: true)
        TestSupport.touch(wrappers.appendingPathComponent("steamwebhelper-wrapper-x64.exe"), contents: Data("WRAPPER".utf8))

        XCTAssertTrue(try SteamInstaller.applyWebHelperWrapper(to: bottle, wrapperDirectory: wrappers))
        XCTAssertEqual(try String(contentsOf: helper), "WRAPPER")
        XCTAssertEqual(try String(contentsOf: cef.appendingPathComponent("steamwebhelper.orig.exe")), "ORIGINAL")

        // Second run is a no-op.
        XCTAssertTrue(try SteamInstaller.applyWebHelperWrapper(to: bottle, wrapperDirectory: wrappers))
        XCTAssertEqual(try String(contentsOf: cef.appendingPathComponent("steamwebhelper.orig.exe")), "ORIGINAL")

        // Steam restored its binary: the new one becomes the original.
        try Data("ORIGINAL-v2".utf8).write(to: helper)
        XCTAssertTrue(try SteamInstaller.applyWebHelperWrapper(to: bottle, wrapperDirectory: wrappers))
        XCTAssertEqual(try String(contentsOf: cef.appendingPathComponent("steamwebhelper.orig.exe")), "ORIGINAL-v2")
        XCTAssertEqual(try String(contentsOf: helper), "WRAPPER")
    }

    /// Current Steam clients (2025+) ship CEF in `bin/cef/cef.win64`; the legacy
    /// `cef.win7x64` / `cef.win7` folders are leftovers that Steam no longer runs.
    func testWrapperIsDeployedToCurrentCEFDirectory() throws {
        let root = TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bottle = TestSupport.makeBottle(in: root)

        let cef = SteamInstaller.steamDirectory(in: bottle).appendingPathComponent("bin/cef/cef.win64")
        let helper = cef.appendingPathComponent("steamwebhelper.exe")
        TestSupport.touch(helper, contents: Data("ORIGINAL".utf8))

        let wrappers = root.appendingPathComponent("wrappers", isDirectory: true)
        TestSupport.touch(wrappers.appendingPathComponent("steamwebhelper-wrapper-x64.exe"), contents: Data("WRAPPER".utf8))

        XCTAssertTrue(try SteamInstaller.applyWebHelperWrapper(to: bottle, wrapperDirectory: wrappers))
        XCTAssertEqual(try String(contentsOf: helper), "WRAPPER")
        XCTAssertEqual(try String(contentsOf: cef.appendingPathComponent("steamwebhelper.orig.exe")), "ORIGINAL")
    }

    func testWrapperWithoutCEFDirectoryIsNoop() throws {
        let root = TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bottle = TestSupport.makeBottle(in: root)
        XCTAssertFalse(try SteamInstaller.applyWebHelperWrapper(to: bottle, wrapperDirectory: root))
    }
}
