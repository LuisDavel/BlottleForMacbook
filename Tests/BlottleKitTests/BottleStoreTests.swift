import XCTest
@testable import BlottleKit

final class BottleStoreTests: XCTestCase {
    func testSaveAndLoadRoundTrip() throws {
        let root = TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BottleStore(directory: root)

        var bottle = Bottle(name: "Jogos", engineID: "gcenx-wine-devel-11.18", url: root.appendingPathComponent("Jogos"))
        bottle.settings.graphics = .dxvk
        bottle.settings.environment = ["A": "1"]
        bottle.pin(Program(name: "Steam", path: "/x/steam.exe", arguments: "-noverifyfiles", kind: .steam))
        try store.save(bottle)

        let loaded = try store.load(at: bottle.url)
        XCTAssertEqual(loaded.id, bottle.id)
        XCTAssertEqual(loaded.name, "Jogos")
        XCTAssertEqual(loaded.settings, bottle.settings)
        XCTAssertEqual(loaded.programs, bottle.programs)
        XCTAssertEqual(loaded.url, bottle.url)

        XCTAssertEqual(store.list().count, 1)
        XCTAssertEqual(store.resolve("jogos")?.id, bottle.id)
        XCTAssertEqual(store.resolve(bottle.id.uuidString)?.id, bottle.id)
        XCTAssertNil(store.resolve("nope"))

        try store.delete(bottle)
        XCTAssertTrue(store.list().isEmpty)
    }

    func testPinReplacesDuplicates() {
        var bottle = Bottle(name: "b", engineID: "e", url: URL(fileURLWithPath: "/tmp/b"))
        bottle.pin(Program(name: "A", path: "/tmp/b/drive_c/a.exe"))
        bottle.pin(Program(name: "A2", path: "/tmp/b/drive_c/A.EXE", arguments: "-x"))
        XCTAssertEqual(bottle.programs.count, 1)
        XCTAssertEqual(bottle.programs.first?.arguments, "-x")
        bottle.unpin(bottle.programs[0])
        XCTAssertTrue(bottle.programs.isEmpty)
    }
}
