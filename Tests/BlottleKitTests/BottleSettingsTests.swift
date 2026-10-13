import XCTest
@testable import BlottleKit

final class BottleSettingsTests: XCTestCase {
    func testDefaultsUseMSyncAndWineD3D() {
        let env = BottleSettings().environmentVariables()
        XCTAssertEqual(env["WINEMSYNC"], "1")
        XCTAssertEqual(env["WINEESYNC"], "1")
        XCTAssertEqual(env["WINEDEBUG"], "fixme-all")
        XCTAssertNil(env["WINEDLLOVERRIDES"])
        XCTAssertNil(env["MTL_HUD_ENABLED"])
    }

    func testDXVKOverridesAndHUD() {
        var settings = BottleSettings()
        settings.graphics = .dxvk
        settings.dxvkHUD = .fps
        settings.dxvkAsync = true
        settings.dllOverrides = ["dinput8": "n,b"]
        let env = settings.environmentVariables()
        XCTAssertEqual(env["WINEDLLOVERRIDES"], "d3d9,d3d10core,d3d11,dxgi=n,b;dinput8=n,b")
        XCTAssertEqual(env["DXVK_HUD"], "fps")
        XCTAssertEqual(env["DXVK_ASYNC"], "1")
    }

    func testD3DMetalFlags() {
        var settings = BottleSettings()
        settings.graphics = .d3dmetal
        settings.dxrEnabled = true
        settings.metalHUD = true
        settings.advertiseAVX = true
        settings.sync = .esync
        let env = settings.environmentVariables()
        XCTAssertEqual(env["D3DM_SUPPORT_DXR"], "1")
        XCTAssertEqual(env["MTL_HUD_ENABLED"], "1")
        XCTAssertEqual(env["ROSETTA_ADVERTISE_AVX"], "1")
        XCTAssertEqual(env["WINEESYNC"], "1")
        XCTAssertNil(env["WINEMSYNC"])
        XCTAssertNil(env["WINEDLLOVERRIDES"])
    }

    func testCustomEnvironmentWins() {
        var settings = BottleSettings()
        settings.environment = ["WINEDEBUG": "+loaddll", "FOO": "bar"]
        let env = settings.environmentVariables()
        XCTAssertEqual(env["WINEDEBUG"], "+loaddll")
        XCTAssertEqual(env["FOO"], "bar")
    }

    func testDecodingToleratesMissingKeys() throws {
        let json = Data(#"{"graphics":"dxvk","dpi":144}"#.utf8)
        let settings = try JSONDecoder().decode(BottleSettings.self, from: json)
        XCTAssertEqual(settings.graphics, .dxvk)
        XCTAssertEqual(settings.dpi, 144)
        XCTAssertEqual(settings.sync, .msync)
        XCTAssertTrue(settings.steamWebHelperFix)
        let roundTrip = try JSONDecoder().decode(BottleSettings.self, from: try JSONEncoder().encode(settings))
        XCTAssertEqual(roundTrip, settings)
    }

    func testGamingDefaultsPickD3DMetalOnlyForGPTKEngines() {
        let gcenx = WineEngine(id: "a", name: "a", version: "", flavor: .wineDevel, root: URL(fileURLWithPath: "/nonexistent"))
        XCTAssertEqual(BottleSettings.gaming(engine: gcenx).graphics, .wined3d)
        XCTAssertEqual(BottleSettings.gaming(engine: nil).sync, .msync)
    }
}
