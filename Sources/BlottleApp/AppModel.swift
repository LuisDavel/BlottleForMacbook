import AppKit
import BlottleKit
import Foundation
import Observation
import UniformTypeIdentifiers

struct BusyState {
    var title: String
    var detail: String = ""
    var progress: Double? = nil
}

struct AlertInfo: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

struct RunningProgram: Identifiable {
    let id = UUID()
    let bottleID: UUID
    let name: String
    let process: LaunchedProcess
}

enum WineTool: String, CaseIterable, Identifiable {
    case winecfg, regedit, taskmgr, control, explorer, cmd

    var id: String { rawValue }

    var title: String {
        switch self {
        case .winecfg: return "Configuração do Wine (winecfg)"
        case .regedit: return "Editor de Registro"
        case .taskmgr: return "Gerenciador de Tarefas"
        case .control: return "Painel de Controle"
        case .explorer: return "Explorer"
        case .cmd: return "Prompt de Comando"
        }
    }
}

/// All UI state plus the glue to BlottleKit. Everything runs on the main actor;
/// long operations are `async` and keep the window responsive.
@MainActor
@Observable
final class AppModel {
    var bottles: [Bottle] = []
    var engines: [WineEngine] = []
    var catalog: [CatalogEntry] = EngineCatalog.builtin
    var selectedBottleID: UUID?
    var programsByBottle: [UUID: [Program]] = [:]
    var running: [RunningProgram] = []
    var busy: BusyState?
    var alert: AlertInfo?
    var showCreateBottle = false

    let store = BottleStore()
    let engineManager = EngineManager()

    init() {
        try? BlottlePaths.ensureDirectories()
        refresh()
    }

    // MARK: - Lookups

    var selectedBottle: Bottle? {
        bottles.first { $0.id == selectedBottleID }
    }

    func engine(for bottle: Bottle) -> WineEngine? {
        engines.first { $0.id == bottle.engineID }
    }

    func programs(for bottle: Bottle) -> [Program] {
        programsByBottle[bottle.id] ?? bottle.programs
    }

    func runningPrograms(in bottle: Bottle) -> [RunningProgram] {
        running.filter { $0.bottleID == bottle.id && $0.process.isRunning }
    }

    // MARK: - Refresh

    func refresh() {
        bottles = store.list()
        engines = engineManager.installed()
        if selectedBottleID == nil || !bottles.contains(where: { $0.id == selectedBottleID }) {
            selectedBottleID = bottles.first?.id
        }
    }

    func refreshPrograms(for bottle: Bottle) async {
        let programs = await Task.detached(priority: .utility) {
            ProgramScanner.allPrograms(in: bottle)
        }.value
        programsByBottle[bottle.id] = programs
    }

    // MARK: - Task plumbing

    func perform(_ title: String, detail: String = "", _ work: @escaping () async throws -> Void) {
        Task { await performAsync(title, detail: detail, work) }
    }

    func performAsync(_ title: String, detail: String = "", _ work: @escaping () async throws -> Void) async {
        busy = BusyState(title: title, detail: detail)
        defer { busy = nil }
        do {
            try await work()
        } catch {
            alert = AlertInfo(title: title, message: error.localizedDescription)
        }
        refresh()
    }

    func setProgress(_ fraction: Double?, detail: String? = nil) {
        if busy != nil {
            busy?.progress = fraction
            if let detail { busy?.detail = detail }
        }
    }

    func report(_ progress: InstallProgress) {
        switch progress {
        case .downloading(let fraction): setProgress(fraction, detail: progress.description)
        default: setProgress(nil, detail: progress.description)
        }
    }

    func fail(_ title: String, _ error: Error) {
        alert = AlertInfo(title: title, message: error.localizedDescription)
    }

    // MARK: - Bottles

    func createBottle(name: String, engine: WineEngine, settings: BottleSettings, location: URL? = nil) {
        perform("Criando garrafa \(name)") { [self] in
            let bottle = try await store.create(name: name, engine: engine, settings: settings, location: location) { status in
                Task { @MainActor in self.setProgress(nil, detail: status) }
            }
            selectedBottleID = bottle.id
        }
    }

    func deleteBottle(_ bottle: Bottle) {
        perform("Apagando \(bottle.name)") { [self] in
            if let engine = engine(for: bottle) {
                try? await WineRunner(engine: engine, bottle: bottle).shutdown()
            }
            try store.delete(bottle)
            programsByBottle[bottle.id] = nil
            if selectedBottleID == bottle.id { selectedBottleID = nil }
        }
    }

    func save(_ bottle: Bottle, applyRegistry: Bool) {
        perform("Salvando configurações") { [self] in
            var updated = bottle
            if applyRegistry, let engine = engine(for: bottle) {
                try await store.applySettings(&updated, engine: engine)
            } else {
                try store.save(updated)
            }
        }
    }

    func killAll(in bottle: Bottle) {
        guard let engine = engine(for: bottle) else { return }
        perform("Encerrando processos de \(bottle.name)") {
            try await WineRunner(engine: engine, bottle: bottle).shutdown()
        }
    }

    // MARK: - Launching

    func launch(_ program: Program, in bottle: Bottle) {
        guard let engine = requireEngine(for: bottle) else { return }
        do {
            let launched = try ProgramLauncher.launch(program, in: bottle, engine: engine) { [weak self] _ in
                Task { @MainActor in self?.pruneRunning() }
            }
            running.append(RunningProgram(bottleID: bottle.id, name: program.name, process: launched))
        } catch {
            fail("Não foi possível abrir \(program.name)", error)
        }
    }

    func launchFile(_ url: URL, in bottle: Bottle, pin: Bool = true) {
        guard let engine = requireEngine(for: bottle) else { return }
        do {
            let launched = try ProgramLauncher.launch(file: url, in: bottle, engine: engine) { [weak self] _ in
                Task { @MainActor in self?.pruneRunning() }
            }
            running.append(RunningProgram(bottleID: bottle.id, name: url.lastPathComponent, process: launched))
            if pin, url.pathExtension.lowercased() == "exe", url.path.hasPrefix(bottle.driveC.path) {
                var updated = bottle
                updated.pin(Program(name: Program.name(forExecutable: url), path: url.path))
                try store.save(updated)
                refresh()
                Task { await refreshPrograms(for: updated) }
            }
        } catch {
            fail("Não foi possível abrir \(url.lastPathComponent)", error)
        }
    }

    func openRunPanel(for bottle: Bottle) {
        let panel = NSOpenPanel()
        panel.title = "Escolha um arquivo Windows"
        panel.message = "Executáveis (.exe), instaladores (.msi), scripts (.bat) e atalhos (.lnk)"
        panel.allowedContentTypes = [
            UTType(filenameExtension: "exe"), UTType(filenameExtension: "msi"),
            UTType(filenameExtension: "bat"), UTType(filenameExtension: "cmd"),
            UTType(filenameExtension: "lnk"), UTType(filenameExtension: "reg"),
        ].compactMap { $0 }
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = bottle.driveC
        if panel.runModal() == .OK, let url = panel.url {
            launchFile(url, in: bottle)
        }
    }

    func pin(_ program: Program, in bottle: Bottle) {
        var updated = bottle
        var pinned = program
        pinned.source = .pinned
        updated.pin(pinned)
        do {
            try store.save(updated)
            refresh()
            Task { await refreshPrograms(for: updated) }
        } catch {
            fail("Não foi possível salvar", error)
        }
    }

    func unpin(_ program: Program, in bottle: Bottle) {
        var updated = bottle
        updated.unpin(program)
        do {
            try store.save(updated)
            refresh()
            Task { await refreshPrograms(for: updated) }
        } catch {
            fail("Não foi possível salvar", error)
        }
    }

    func updateProgram(_ program: Program, in bottle: Bottle) {
        var updated = bottle
        updated.pin(program)
        do {
            try store.save(updated)
            refresh()
            Task { await refreshPrograms(for: updated) }
        } catch {
            fail("Não foi possível salvar", error)
        }
    }

    func open(_ tool: WineTool, in bottle: Bottle) {
        guard let engine = requireEngine(for: bottle) else { return }
        let runner = WineRunner(engine: engine, bottle: bottle)
        do {
            let launched: LaunchedProcess
            switch tool {
            case .winecfg: launched = try runner.openWinecfg()
            case .regedit: launched = try runner.openRegedit()
            case .taskmgr: launched = try runner.openTaskManager()
            case .control: launched = try runner.openControlPanel()
            case .explorer: launched = try runner.openExplorer()
            case .cmd: launched = try runner.openCommandPrompt()
            }
            running.append(RunningProgram(bottleID: bottle.id, name: tool.rawValue, process: launched))
        } catch {
            fail("Não foi possível abrir \(tool.title)", error)
        }
    }

    func pruneRunning() {
        running.removeAll { !$0.process.isRunning }
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openCDrive(_ bottle: Bottle) {
        NSWorkspace.shared.open(bottle.driveC)
    }

    func openLogsFolder(_ bottle: Bottle) {
        let directory = BlottleLog.directory(forBottle: bottle.name)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    private func requireEngine(for bottle: Bottle) -> WineEngine? {
        if let engine = engine(for: bottle) { return engine }
        alert = AlertInfo(
            title: "Engine ausente",
            message: "A garrafa \(bottle.name) usa a engine \(bottle.engineID), que não está instalada. Instale-a em Ajustes › Engines ou troque a engine da garrafa."
        )
        return nil
    }

    // MARK: - Engines

    func fetchRemoteCatalog() async {
        if let remote = try? await EngineCatalog.fetchRemote() {
            catalog = EngineCatalog.merged(remote: remote)
        }
    }

    func installEngine(_ entry: CatalogEntry) {
        perform("Instalando \(entry.name)") { [self] in
            _ = try await engineManager.install(entry) { progress in
                Task { @MainActor in self.report(progress) }
            }
        }
    }

    func importEngine(from url: URL, flavor: EngineFlavor? = nil) {
        perform("Importando Wine de \(url.lastPathComponent)") { [self] in
            _ = try await engineManager.importEngine(from: url, flavor: flavor)
        }
    }

    /// Lets the user pick a parent folder for a new bottle (e.g. on an external SSD).
    func chooseBottleLocationPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Escolha a pasta onde a garrafa será criada"
        panel.message = "A garrafa vira uma subpasta aqui. Discos externos precisam estar formatados como APFS."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Volumes")
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try BottleStore.validateLocation(url)
        } catch {
            alert = AlertInfo(title: "Pasta não suportada", message: error.localizedDescription)
            return nil
        }
        return url
    }

    func importEnginePanel() {
        let panel = NSOpenPanel()
        panel.title = "Escolha um Wine (.app ou pasta com bin/wine)"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            importEngine(from: url)
        }
    }

    func removeEngine(_ engine: WineEngine) {
        perform("Removendo \(engine.name)") { [self] in
            try engineManager.remove(engine)
        }
    }

    func installD3DMetalPanel(into engine: WineEngine) {
        let panel = NSOpenPanel()
        panel.title = "Escolha o Game Porting Toolkit (.dmg) baixado da Apple"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            perform("Instalando D3DMetal em \(engine.name)") {
                try await D3DMetalInstaller.install(from: url, into: engine)
            }
        }
    }

    // MARK: - Graphics

    func installDXVK(in bottle: Bottle) {
        perform("Instalando DXVK em \(bottle.name)") { [self] in
            try await DXVKInstaller.install(into: bottle) { progress in
                Task { @MainActor in self.report(progress) }
            }
            var updated = bottle
            updated.settings.graphics = .dxvk
            try store.save(updated)
        }
    }

    func removeDXVK(in bottle: Bottle) {
        perform("Removendo DXVK de \(bottle.name)") { [self] in
            try DXVKInstaller.uninstall(from: bottle)
            var updated = bottle
            if updated.settings.graphics == .dxvk { updated.settings.graphics = .wined3d }
            try store.save(updated)
        }
    }

    func installDXMTPanel(in bottle: Bottle) {
        guard let engine = requireEngine(for: bottle) else { return }
        let panel = NSOpenPanel()
        panel.title = "Escolha o pacote DXMT (.tar.gz)"
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            perform("Instalando DXMT em \(bottle.name)") { [self] in
                try await DXMTInstaller.install(archive: url, into: bottle, engine: engine)
                var updated = bottle
                updated.settings.graphics = .dxmt
                try store.save(updated)
            }
        }
    }

    // MARK: - Steam & winetricks

    func installSteam(in bottle: Bottle, options: SteamOptions, gaming: Bool) {
        guard let engine = requireEngine(for: bottle) else { return }
        perform("Instalando Steam em \(bottle.name)") { [self] in
            var updated = bottle
            if gaming {
                let defaults = BottleSettings.gaming(engine: engine)
                updated.settings.sync = defaults.sync
                updated.settings.graphics = defaults.graphics
            }
            try await SteamInstaller.install(into: &updated, engine: engine, options: options) { status in
                Task { @MainActor in self.setProgress(nil, detail: status) }
            }
            try store.save(updated)
            await refreshPrograms(for: updated)
        }
    }

    func runWinetricks(_ verbs: [String], in bottle: Bottle) {
        guard let engine = requireEngine(for: bottle) else { return }
        perform("winetricks \(verbs.joined(separator: " "))", detail: "Isso pode demorar alguns minutos.") { [self] in
            let result = try await Winetricks.run(verbs: verbs, runner: WineRunner(engine: engine, bottle: bottle))
            guard result.succeeded else {
                throw BlottleError.processFailed(command: "winetricks", exitCode: result.exitCode, output: result.output)
            }
            await refreshPrograms(for: bottle)
        }
    }
}
