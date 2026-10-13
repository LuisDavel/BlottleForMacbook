import XCTest
@testable import BlottleKit

final class MiscTests: XCTestCase {
    func testRegistryQueryParsing() {
        let output = """
        HKEY_CURRENT_USER\\Software\\Wine\\Mac Driver
            RetinaMode    REG_SZ    Y

        """
        XCTAssertEqual(WineRegistry.parseQueryOutput(output, name: "RetinaMode"), "Y")
        XCTAssertNil(WineRegistry.parseQueryOutput(output, name: "Other"))
    }

    func testLauncherArgumentsByExtension() {
        let exe = URL(fileURLWithPath: "/b/drive_c/app.exe")
        XCTAssertEqual(ProgramLauncher.wineArguments(for: exe, arguments: ["-x"]), ["/b/drive_c/app.exe", "-x"])
        XCTAssertEqual(ProgramLauncher.wineArguments(for: URL(fileURLWithPath: "/b/setup.msi"), arguments: []), ["msiexec", "/i", "/b/setup.msi"])
        XCTAssertEqual(ProgramLauncher.wineArguments(for: URL(fileURLWithPath: "/b/run.bat"), arguments: ["1"]), ["cmd", "/c", "/b/run.bat", "1"])
        XCTAssertEqual(ProgramLauncher.wineArguments(for: URL(fileURLWithPath: "/b/k.reg"), arguments: []), ["regedit", "/S", "/b/k.reg"])
        XCTAssertEqual(ProgramLauncher.wineArguments(for: URL(fileURLWithPath: "/b/s.lnk"), arguments: []), ["start", "/unix", "/b/s.lnk"])
    }

    func testArchiveKindDetection() {
        XCTAssertEqual(Archive.Kind.detect(from: URL(fileURLWithPath: "/x/wine.tar.xz")), .tarXZ)
        XCTAssertEqual(Archive.Kind.detect(from: URL(fileURLWithPath: "/x/dxvk.tar.gz")), .tarGZ)
        XCTAssertEqual(Archive.Kind.detect(from: URL(fileURLWithPath: "/x/GPTK.dmg")), .dmg)
        XCTAssertEqual(Archive.Kind.detect(from: URL(fileURLWithPath: "/x/a.zip")), .zip)
        XCTAssertNil(Archive.Kind.detect(from: URL(fileURLWithPath: "/x/a.exe")))
    }

    func testLogNameSanitization() {
        XCTAssertEqual(BlottleLog.sanitize("Jogos/Steam: x"), "Jogos_Steam_ x")
        XCTAssertEqual(BlottleLog.sanitize("   "), "bottle")
    }

    func testProcessRunnerCapturesOutput() async throws {
        let result = try await ProcessRunner.run(URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "echo hello; exit 3"])
        XCTAssertEqual(result.exitCode, 3)
        XCTAssertTrue(result.output.contains("hello"))
        let ok = try await ProcessRunner.check(URL(fileURLWithPath: "/usr/bin/true"))
        XCTAssertTrue(ok.succeeded)
    }
}
