import XCTest
@testable import BlottleKit

final class EngineManagerTests: XCTestCase {
    func testLocatesWineRootInsideAppBundle() {
        let root = TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Wine Devel.app", isDirectory: true)
        let wineRoot = TestSupport.makeFakeWineRoot(at: app.appendingPathComponent("Contents/Resources/wine", isDirectory: true), binaryName: "wine64")

        XCTAssertEqual(WineEngine.locateRoot(in: app)?.standardizedFileURL, wineRoot.standardizedFileURL)
        XCTAssertEqual(WineEngine.guessFlavor(for: wineRoot), .wineDevel)
        let engine = WineEngine(id: "x", name: "x", version: "", flavor: .wineDevel, root: wineRoot)
        XCTAssertEqual(engine.wineBinary.lastPathComponent, "wine64")
        XCTAssertTrue(engine.isValid)
        XCTAssertFalse(engine.supportsD3DMetal)
    }

    func testImportAndListRoundTrip() async throws {
        let root = TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let wineRoot = TestSupport.makeFakeWineRoot(at: root.appendingPathComponent("external-wine", isDirectory: true))
        let manager = EngineManager(directory: root.appendingPathComponent("Engines", isDirectory: true))

        let imported = try await manager.importEngine(from: wineRoot, name: "Meu Wine", flavor: .custom)
        XCTAssertEqual(imported.id, "meu-wine")
        XCTAssertEqual(imported.version, "wine-9.0-fake")

        let listed = manager.installed()
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed.first?.name, "Meu Wine")
        XCTAssertEqual(listed.first?.root.standardizedFileURL, wineRoot.standardizedFileURL)
        XCTAssertNotNil(manager.engine(id: "meu-wine"))

        let second = try await manager.importEngine(from: wineRoot, name: "Meu Wine", flavor: .custom)
        XCTAssertEqual(second.id, "meu-wine-2")

        try manager.remove(imported)
        XCTAssertEqual(manager.installed().count, 1)
    }

    func testSlug() {
        XCTAssertEqual(EngineManager.slug("Wine Devel 11.18 (Gcenx)"), "wine-devel-11.18-gcenx")
        XCTAssertEqual(EngineManager.slug("///"), "engine")
    }

    func testCatalogEntriesDecodeFromJSON() throws {
        let data = try JSONEncoder().encode(EngineCatalog.builtin)
        let decoded = try JSONDecoder().decode([CatalogEntry].self, from: data)
        XCTAssertEqual(decoded, EngineCatalog.builtin)
        let merged = EngineCatalog.merged(remote: [CatalogEntry(
            id: EngineCatalog.builtin[0].id, name: "Newer", version: "99", flavor: .wineDevel,
            url: URL(string: "https://example.com/x.tar.xz")!, archive: .tarXZ
        )])
        XCTAssertEqual(merged.count, EngineCatalog.builtin.count)
        XCTAssertTrue(merged.contains { $0.name == "Newer" })
    }
}
