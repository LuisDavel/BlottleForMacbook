import Foundation

/// A downloadable Wine build.
public struct CatalogEntry: Identifiable, Hashable, Codable, Sendable {
    public enum Status: String, Codable, Sendable {
        case stable
        case experimental
        /// The host went away (or may go away); keep the entry so users can point at a mirror.
        case maybeOffline
    }

    public var id: String
    public var name: String
    public var version: String
    public var flavor: EngineFlavor
    public var url: URL
    public var sha256: String?
    public var archive: Archive.Kind
    public var status: Status
    public var notes: String

    public init(
        id: String,
        name: String,
        version: String,
        flavor: EngineFlavor,
        url: URL,
        sha256: String? = nil,
        archive: Archive.Kind,
        status: Status = .stable,
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.flavor = flavor
        self.url = url
        self.sha256 = sha256
        self.archive = archive
        self.status = status
        self.notes = notes
    }
}

/// Built-in list of Wine builds Blottle knows how to download.
///
/// A newer list can be fetched from `remoteURL`; the JSON has the same shape
/// as `[CatalogEntry]`, so the project can publish updates without a new app
/// release.
public enum EngineCatalog {
    public static let remoteURL = URL(string:
        "https://raw.githubusercontent.com/LuisDavel/BlottleForMacbook/main/catalog/engines.json")!

    public static let builtin: [CatalogEntry] = [
        CatalogEntry(
            id: "gcenx-wine-devel-11.18",
            name: "Wine Devel 11.18",
            version: "11.18",
            flavor: .wineDevel,
            url: URL(string: "https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.18/wine-devel-11.18-osx64.tar.xz")!,
            archive: .tarXZ,
            status: .stable,
            notes: "Build oficial do WineHQ empacotado por Gcenx. Inclui wine-gecko e wine-mono. Usa Rosetta 2 em Apple Silicon. DirectX 10/11 via DXVK (MoltenVK) ou WineD3D."
        ),
        CatalogEntry(
            id: "gcenx-wine-staging-11.18",
            name: "Wine Staging 11.18",
            version: "11.18",
            flavor: .wineStaging,
            url: URL(string: "https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.18/wine-staging-11.18-osx64.tar.xz")!,
            archive: .tarXZ,
            status: .stable,
            notes: "Wine Staging com patches experimentais. Melhor compatibilidade com alguns launchers."
        ),
        CatalogEntry(
            id: "whisky-wine-gptk",
            name: "WhiskyWine (GPTK)",
            version: "2.x",
            flavor: .whisky,
            url: URL(string: "https://data.getwhisky.app/Wine/Libraries.tar.gz")!,
            archive: .tarGZ,
            status: .maybeOffline,
            notes: "Wine do Whisky, compilado a partir das fontes do Game Porting Toolkit. Suporta D3DMetal (DirectX 11/12) depois de instalar as bibliotecas da Apple. O Whisky foi descontinuado; o servidor pode sair do ar."
        ),
    ]

    public static func fetchRemote() async throws -> [CatalogEntry] {
        let (data, response) = try await URLSession.shared.data(from: remoteURL)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw BlottleError.downloadFailed("catálogo remoto respondeu HTTP \(http.statusCode)")
        }
        return try JSONDecoder().decode([CatalogEntry].self, from: data)
    }

    /// Built-in entries merged with a remote list (remote wins on id collisions).
    public static func merged(remote: [CatalogEntry]) -> [CatalogEntry] {
        var byID: [String: CatalogEntry] = [:]
        for entry in builtin { byID[entry.id] = entry }
        for entry in remote { byID[entry.id] = entry }
        return byID.values.sorted { $0.name < $1.name }
    }
}
