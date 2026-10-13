import XCTest
@testable import BlottleKit

final class DXVKInstallerTests: XCTestCase {
    func testInstallFromLocalArchiveAndUninstall() async throws {
        let root = TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bottle = TestSupport.makeBottle(in: root)
        TestSupport.touch(bottle.system32.appendingPathComponent("d3d11.dll"), contents: Data("builtin".utf8))

        // Build a fake dxvk tarball: dxvk/x64/{d3d11,dxgi}.dll, dxvk/x32/d3d11.dll
        let payload = root.appendingPathComponent("payload/dxvk", isDirectory: true)
        TestSupport.touch(payload.appendingPathComponent("x64/d3d11.dll"), contents: Data("dxvk64".utf8))
        TestSupport.touch(payload.appendingPathComponent("x64/dxgi.dll"), contents: Data("dxvk64".utf8))
        TestSupport.touch(payload.appendingPathComponent("x32/d3d11.dll"), contents: Data("dxvk32".utf8))
        let archive = root.appendingPathComponent("dxvk.tar.gz")
        try await ProcessRunner.check(
            URL(fileURLWithPath: "/usr/bin/tar"),
            arguments: ["-czf", archive.path, "-C", payload.deletingLastPathComponent().path, "dxvk"]
        )

        let installed = try await DXVKInstaller.install(into: bottle, archive: archive)
        XCTAssertEqual(Set(installed), ["d3d11", "dxgi"])
        XCTAssertTrue(DXVKInstaller.isInstalled(in: bottle))
        XCTAssertEqual(try String(contentsOf: bottle.system32.appendingPathComponent("d3d11.dll")), "dxvk64")
        XCTAssertEqual(try String(contentsOf: bottle.system32.appendingPathComponent("d3d11.dll.wined3d")), "builtin")
        XCTAssertEqual(try String(contentsOf: bottle.sysWOW64.appendingPathComponent("d3d11.dll")), "dxvk32")

        try DXVKInstaller.uninstall(from: bottle)
        XCTAssertFalse(DXVKInstaller.isInstalled(in: bottle))
        XCTAssertEqual(try String(contentsOf: bottle.system32.appendingPathComponent("d3d11.dll")), "builtin")
        XCTAssertFalse(FileManager.default.fileExists(atPath: bottle.system32.appendingPathComponent("d3d11.dll.wined3d").path))
    }
}
