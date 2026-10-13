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

final class ExternalBottleTests: XCTestCase {
    private func makeStore(root: URL) -> BottleStore {
        BottleStore(directory: root.appendingPathComponent("Bottles"), registryFile: root.appendingPathComponent("ExternalBottles.json"))
    }

    func testExternalBottleIsRegisteredAndListed() throws {
        let root = TestSupport.temporaryDirectory()
        let external = TestSupport.temporaryDirectory("blottle-external")
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: external) }
        let store = makeStore(root: root)

        let url = try store.allocateFolder(name: "Jogos", location: external)
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL, external.standardizedFileURL)
        let bottle = Bottle(name: "Jogos", engineID: "e", url: url)
        try store.save(bottle)

        XCTAssertEqual(store.list().map(\.name), ["Jogos"])
        XCTAssertEqual(store.resolve("jogos")?.url.standardizedFileURL, url.standardizedFileURL)
        XCTAssertEqual(store.externalLocations().map(\.standardizedFileURL), [url.standardizedFileURL])

        // A second store instance (e.g. the CLI) sees the same registry.
        XCTAssertEqual(makeStore(root: root).list().count, 1)
    }

    func testAllocateFolderAvoidsCollisions() throws {
        let root = TestSupport.temporaryDirectory()
        let external = TestSupport.temporaryDirectory("blottle-external")
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: external) }
        let store = makeStore(root: root)

        try FileManager.default.createDirectory(at: external.appendingPathComponent("Jogos"), withIntermediateDirectories: true)
        let url = try store.allocateFolder(name: "Jogos", location: external)
        XCTAssertEqual(url.lastPathComponent, "Jogos-2")
    }

    func testMissingExternalBottleIsSkippedButKept() throws {
        let root = TestSupport.temporaryDirectory()
        let external = TestSupport.temporaryDirectory("blottle-external")
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: external) }
        let store = makeStore(root: root)

        let url = try store.allocateFolder(name: "SSD", location: external)
        try store.save(Bottle(name: "SSD", engineID: "e", url: url))
        XCTAssertEqual(store.list().count, 1)

        // Simulate the disk being unplugged.
        try FileManager.default.removeItem(at: external)
        XCTAssertTrue(store.list().isEmpty)
        XCTAssertEqual(store.externalLocations().count, 1, "registry keeps the path so the bottle comes back when the disk is plugged in")
    }

    func testDeleteUnregistersExternalBottle() throws {
        let root = TestSupport.temporaryDirectory()
        let external = TestSupport.temporaryDirectory("blottle-external")
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: external) }
        let store = makeStore(root: root)

        let url = try store.allocateFolder(name: "SSD", location: external)
        let bottle = Bottle(name: "SSD", engineID: "e", url: url)
        try store.save(bottle)
        try store.delete(bottle)
        XCTAssertTrue(store.list().isEmpty)
        XCTAssertTrue(store.externalLocations().isEmpty)
    }

    func testDefaultLocationIsNotRegistered() throws {
        let root = TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = makeStore(root: root)

        let url = try store.allocateFolder(name: "Local", location: nil)
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL, store.directory.standardizedFileURL)
        XCTAssertTrue(store.externalLocations().isEmpty)
    }

    func testVolumeValidationAcceptsAPFSTemporaryDirectory() throws {
        let dir = TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertNoThrow(try BottleStore.validateLocation(dir))
    }

    func testVolumeValidationRejectsMissingDirectory() {
        let missing = URL(fileURLWithPath: "/Volumes/does-not-exist-\(UUID().uuidString)")
        XCTAssertThrowsError(try BottleStore.validateLocation(missing))
    }
}
