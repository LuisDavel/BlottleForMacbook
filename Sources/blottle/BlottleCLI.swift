import ArgumentParser
import BlottleKit
import Foundation

@main
struct BlottleCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "blottle",
        abstract: "Rode programas Windows (.exe) e jogos da Steam no seu Mac, estilo CrossOver.",
        version: "0.1.0",
        subcommands: [
            EngineCommand.self,
            BottleCommand.self,
            RunCommand.self,
            SteamCommand.self,
            WinetricksCommand.self,
            DXVKCommand.self,
            D3DMetalCommand.self,
            DXMTCommand.self,
            DoctorCommand.self,
        ]
    )
}

// MARK: - Shared helpers

enum CLI {
    static let store = BottleStore()
    static let engines = EngineManager()

    static func bottle(_ reference: String) throws -> Bottle {
        guard let bottle = store.resolve(reference) else {
            throw BlottleError.bottleNotFound(reference)
        }
        return bottle
    }

    static func engine(for bottle: Bottle) throws -> WineEngine {
        guard let engine = engines.engine(id: bottle.engineID) else {
            throw BlottleError.engineNotFound(bottle.engineID)
        }
        return engine
    }

    static func engine(_ reference: String?) throws -> WineEngine {
        if let reference {
            if let engine = engines.engine(id: reference) { return engine }
            if let engine = engines.installed().first(where: { $0.name.caseInsensitiveCompare(reference) == .orderedSame }) {
                return engine
            }
            throw BlottleError.engineNotFound(reference)
        }
        guard let first = engines.installed().first else {
            throw BlottleError.engineNotFound("(nenhuma instalada)")
        }
        return first
    }

    static func printProgress(_ message: String) {
        FileHandle.standardError.write(Data(("» " + message + "\n").utf8))
    }

    static func progressBar(_ progress: InstallProgress) {
        FileHandle.standardError.write(Data(("\r» " + progress.description + "          ").utf8))
        if case .finishing = progress { FileHandle.standardError.write(Data("\n".utf8)) }
    }
}

// MARK: - engine

struct EngineCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "engine",
        abstract: "Gerencia as versões do Wine (engines).",
        subcommands: [List.self, Catalog.self, Install.self, Import.self, Detect.self, Remove.self],
        defaultSubcommand: List.self
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Lista engines instaladas.")

        func run() async throws {
            let engines = CLI.engines.installed()
            if engines.isEmpty {
                print("Nenhuma engine instalada. Use `blottle engine catalog` e `blottle engine install <id>`.")
                return
            }
            for engine in engines {
                let d3dm = engine.hasD3DMetal ? " [D3DMetal]" : (engine.supportsD3DMetal ? " [D3DMetal: faltam libs]" : "")
                print("\(engine.id)\t\(engine.name)\t\(engine.displayVersion)\t\(engine.flavor.displayName)\(d3dm)")
                print("    \(engine.root.path)")
            }
        }
    }

    struct Catalog: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Mostra as engines disponíveis para download.")

        @Flag(name: .long, help: "Também consulta o catálogo remoto.")
        var remote = false

        func run() async throws {
            var entries = EngineCatalog.builtin
            if remote {
                do {
                    entries = EngineCatalog.merged(remote: try await EngineCatalog.fetchRemote())
                } catch {
                    CLI.printProgress("catálogo remoto indisponível: \(error.localizedDescription)")
                }
            }
            for entry in entries {
                print("\(entry.id)\t\(entry.name)\t\(entry.flavor.displayName)\t[\(entry.status.rawValue)]")
                print("    \(entry.notes)")
            }
        }
    }

    struct Install: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Baixa e instala uma engine do catálogo.")

        @Argument(help: "Id da engine (veja `blottle engine catalog`).")
        var id: String

        func run() async throws {
            try BlottlePaths.ensureDirectories()
            var entries = EngineCatalog.builtin
            if let remote = try? await EngineCatalog.fetchRemote() {
                entries = EngineCatalog.merged(remote: remote)
            }
            guard let entry = entries.first(where: { $0.id == id }) else {
                throw BlottleError.engineNotFound(id)
            }
            let engine = try await CLI.engines.install(entry) { CLI.progressBar($0) }
            print("Engine instalada: \(engine.name) (\(engine.displayVersion)) em \(engine.root.path)")
        }
    }

    struct Import: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Registra um Wine já instalado (CrossOver, GPTK, Wine.app…).")

        @Argument(help: "Pasta ou .app contendo bin/wine.", completion: .directory)
        var path: String

        @Option(name: .long, help: "Nome amigável.")
        var name: String?

        @Option(name: .long, help: "Tipo: \(EngineFlavor.allCases.map(\.rawValue).joined(separator: ", ")).")
        var flavor: String?

        func run() async throws {
            try BlottlePaths.ensureDirectories()
            let resolvedFlavor = try flavor.map { raw -> EngineFlavor in
                guard let value = EngineFlavor(rawValue: raw) else {
                    throw ValidationError("flavor inválido: \(raw)")
                }
                return value
            }
            let engine = try await CLI.engines.importEngine(
                from: URL(fileURLWithPath: path),
                name: name,
                flavor: resolvedFlavor
            )
            print("Engine importada: \(engine.id) (\(engine.displayVersion))")
        }
    }

    struct Detect: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Procura instalações de Wine conhecidas neste Mac.")

        func run() async throws {
            let candidates = EngineManager.systemCandidates()
            if candidates.isEmpty {
                print("Nenhum Wine conhecido encontrado em /Applications ou no Homebrew.")
                return
            }
            for candidate in candidates {
                print("\(candidate.name)\t\(candidate.flavor.displayName)\t\(candidate.url.path)")
            }
            print("\nImporte com: blottle engine import \"<caminho>\"")
        }
    }

    struct Remove: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Remove uma engine instalada.")

        @Argument var id: String

        func run() async throws {
            let engine = try CLI.engine(id)
            try CLI.engines.remove(engine)
            print("Engine removida: \(engine.id)")
        }
    }
}

// MARK: - bottle

struct BottleCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bottle",
        abstract: "Cria e administra garrafas (prefixos Wine).",
        subcommands: [
            List.self, Create.self, Delete.self, Config.self, Programs.self, Kill.self,
            Winecfg.self, Regedit.self, Cmd.self, Open.self, Logs.self,
        ],
        defaultSubcommand: List.self
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Lista garrafas.")

        func run() async throws {
            let bottles = CLI.store.list()
            if bottles.isEmpty {
                print("Nenhuma garrafa. Crie uma com `blottle bottle create <nome>`.")
                return
            }
            for bottle in bottles {
                let steam = SteamInstaller.isInstalled(in: bottle) ? " [Steam]" : ""
                print("\(bottle.name)\t\(bottle.settings.windowsVersion.displayName)\t\(bottle.settings.graphics.displayName)\tengine=\(bottle.engineID)\(steam)")
                print("    \(bottle.url.path)")
            }
        }
    }

    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Cria uma garrafa nova e inicializa o prefixo.")

        @Argument(help: "Nome da garrafa.")
        var name: String

        @Option(name: .long, help: "Id da engine (padrão: a primeira instalada).")
        var engine: String?

        @Option(name: .long, help: "Versão do Windows: \(WindowsVersion.allCases.map(\.rawValue).joined(separator: ", ")).")
        var windows: String = WindowsVersion.win10.rawValue

        @Flag(name: .long, help: "Usa os padrões para jogos (MSync, D3DMetal quando disponível).")
        var gaming = false

        @Option(name: .long, help: "Pasta onde a garrafa será criada (ex.: /Volumes/SSD/Bottles). Padrão: Application Support/Blottle/Bottles.", completion: .directory)
        var location: String?

        func run() async throws {
            try BlottlePaths.ensureDirectories()
            let engine = try CLI.engine(self.engine)
            guard let version = WindowsVersion(rawValue: windows) else {
                throw ValidationError("versão do Windows inválida: \(windows)")
            }
            var settings = gaming ? BottleSettings.gaming(engine: engine) : BottleSettings()
            settings.windowsVersion = version
            let location = self.location.map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath, isDirectory: true) }
            let bottle = try await CLI.store.create(name: name, engine: engine, settings: settings, location: location) {
                CLI.printProgress($0)
            }
            print("Garrafa criada: \(bottle.name) em \(bottle.url.path)")
        }
    }

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Apaga uma garrafa e todo o seu conteúdo.")

        @Argument var bottle: String

        @Flag(name: .shortAndLong, help: "Não pede confirmação.")
        var yes = false

        func run() async throws {
            let bottle = try CLI.bottle(self.bottle)
            if !yes {
                print("Apagar \"\(bottle.name)\" (\(bottle.url.path))? [s/N] ", terminator: "")
                guard let answer = readLine()?.lowercased(), answer == "s" || answer == "sim" || answer == "y" else {
                    print("Cancelado.")
                    return
                }
            }
            if let engine = try? CLI.engine(for: bottle) {
                try? await WineRunner(engine: engine, bottle: bottle).shutdown()
            }
            try CLI.store.delete(bottle)
            print("Garrafa apagada.")
        }
    }

    struct Config: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Mostra ou altera configurações de uma garrafa.")

        @Argument var bottle: String

        @Option(name: .long, help: "Versão do Windows (win7, win8, win81, win10, win11).")
        var windows: String?

        @Option(name: .long, help: "Sincronização: none, esync, msync.")
        var sync: String?

        @Option(name: .long, help: "Backend gráfico: wined3d, d3dmetal, dxvk, dxmt.")
        var graphics: String?

        @Option(name: .long, help: "Modo Retina (true/false).")
        var retina: Bool?

        @Option(name: .long, help: "DPI (96 = 100%).")
        var dpi: Int?

        @Option(name: .long, help: "HUD do Metal (true/false).")
        var metalHud: Bool?

        @Option(name: .long, help: "Anunciar AVX ao Rosetta (true/false).")
        var avx: Bool?

        @Option(name: .long, help: "Valor de WINEDEBUG.")
        var wineDebug: String?

        @Option(name: .long, parsing: .upToNextOption, help: "Variáveis de ambiente extra, no formato CHAVE=VALOR.")
        var env: [String] = []

        @Option(name: .long, parsing: .upToNextOption, help: "Overrides de DLL, no formato dll=n,b.")
        var dll: [String] = []

        @Option(name: .long, help: "Troca a engine da garrafa.")
        var engine: String?

        func run() async throws {
            var bottle = try CLI.bottle(self.bottle)
            var changed = false
            var registryChanged = false

            if let windows {
                guard let value = WindowsVersion(rawValue: windows) else { throw ValidationError("versão inválida: \(windows)") }
                bottle.settings.windowsVersion = value
                changed = true
                registryChanged = true
            }
            if let sync {
                guard let value = SyncMode(rawValue: sync) else { throw ValidationError("sync inválido: \(sync)") }
                bottle.settings.sync = value
                changed = true
            }
            if let graphics {
                guard let value = GraphicsBackend(rawValue: graphics) else { throw ValidationError("backend inválido: \(graphics)") }
                bottle.settings.graphics = value
                changed = true
            }
            if let retina { bottle.settings.retinaMode = retina; changed = true; registryChanged = true }
            if let dpi { bottle.settings.dpi = dpi; changed = true; registryChanged = true }
            if let metalHud { bottle.settings.metalHUD = metalHud; changed = true }
            if let avx { bottle.settings.advertiseAVX = avx; changed = true }
            if let wineDebug { bottle.settings.wineDebug = wineDebug; changed = true }
            for pair in env {
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { throw ValidationError("variável inválida: \(pair)") }
                bottle.settings.environment[parts[0]] = parts[1]
                changed = true
            }
            for pair in dll {
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { throw ValidationError("override inválido: \(pair)") }
                bottle.settings.dllOverrides[parts[0]] = parts[1]
                changed = true
            }
            if let engine {
                bottle.engineID = try CLI.engine(engine).id
                changed = true
            }

            if changed {
                let engine = try CLI.engine(for: bottle)
                if registryChanged {
                    try await CLI.store.applySettings(&bottle, engine: engine)
                } else {
                    try CLI.store.save(bottle)
                }
                print("Configurações salvas.")
            }

            let s = bottle.settings
            print("""
            Garrafa:        \(bottle.name)
            Pasta:          \(bottle.url.path)
            Engine:         \(bottle.engineID)
            Windows:        \(s.windowsVersion.displayName)
            Sync:           \(s.sync.displayName)
            Gráficos:       \(s.graphics.displayName)
            Retina:         \(s.retinaMode)   DPI: \(s.dpi)
            Metal HUD:      \(s.metalHUD)   AVX: \(s.advertiseAVX)
            WINEDEBUG:      \(s.wineDebug)
            Env extra:      \(s.environment.isEmpty ? "-" : s.environment.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " "))
            DLL overrides:  \(s.dllOverrides.isEmpty ? "-" : s.dllOverrides.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ";"))
            """)
        }
    }

    struct Programs: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Lista programas instalados na garrafa.")

        @Argument var bottle: String

        func run() async throws {
            let bottle = try CLI.bottle(self.bottle)
            let programs = ProgramScanner.allPrograms(in: bottle)
            if programs.isEmpty {
                print("Nenhum programa encontrado.")
                return
            }
            for program in programs {
                let args = program.arguments.isEmpty ? "" : "  args: \(program.arguments)"
                print("[\(program.source.rawValue)] \(program.name)\t\(program.path)\(args)")
            }
        }
    }

    struct Kill: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Encerra todos os processos da garrafa (wineserver -k).")

        @Argument var bottle: String

        func run() async throws {
            let bottle = try CLI.bottle(self.bottle)
            let engine = try CLI.engine(for: bottle)
            try await WineRunner(engine: engine, bottle: bottle).shutdown()
            print("Processos encerrados.")
        }
    }

    struct Winecfg: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Abre o winecfg.")
        @Argument var bottle: String
        func run() async throws {
            let bottle = try CLI.bottle(self.bottle)
            let engine = try CLI.engine(for: bottle)
            let process = try WineRunner(engine: engine, bottle: bottle).openWinecfg()
            print("winecfg aberto (log: \(process.logURL.path))")
            process.process.waitUntilExit()
        }
    }

    struct Regedit: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Abre o editor de registro.")
        @Argument var bottle: String
        func run() async throws {
            let bottle = try CLI.bottle(self.bottle)
            let engine = try CLI.engine(for: bottle)
            let process = try WineRunner(engine: engine, bottle: bottle).openRegedit()
            process.process.waitUntilExit()
        }
    }

    struct Cmd: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Abre um prompt de comando do Windows.")
        @Argument var bottle: String
        func run() async throws {
            let bottle = try CLI.bottle(self.bottle)
            let engine = try CLI.engine(for: bottle)
            let process = try WineRunner(engine: engine, bottle: bottle).openCommandPrompt()
            process.process.waitUntilExit()
        }
    }

    struct Open: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Abre a unidade C: no Finder.")
        @Argument var bottle: String
        func run() async throws {
            let bottle = try CLI.bottle(self.bottle)
            try await ProcessRunner.check(URL(fileURLWithPath: "/usr/bin/open"), arguments: [bottle.driveC.path])
        }
    }

    struct Logs: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Mostra os logs mais recentes da garrafa.")
        @Argument var bottle: String
        @Option(name: .shortAndLong, help: "Quantas linhas do último log exibir.") var lines: Int = 60
        func run() async throws {
            let bottle = try CLI.bottle(self.bottle)
            let logs = BlottleLog.recent(bottle: bottle.name)
            guard let latest = logs.first else {
                print("Sem logs em \(BlottleLog.directory(forBottle: bottle.name).path)")
                return
            }
            print("== \(latest.path)")
            let content = (try? String(contentsOf: latest, encoding: .utf8)) ?? ""
            print(content.split(separator: "\n", omittingEmptySubsequences: false).suffix(lines).joined(separator: "\n"))
        }
    }
}

// MARK: - run

struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Executa um .exe/.msi/.bat/.lnk dentro de uma garrafa."
    )

    @Argument(help: "Nome da garrafa.")
    var bottle: String

    @Argument(help: "Arquivo a executar (ou nome de um programa já listado).", completion: .file())
    var file: String

    @Argument(parsing: .captureForPassthrough, help: "Argumentos para o programa.")
    var arguments: [String] = []

    @Flag(name: .long, help: "Não espera o programa terminar.")
    var detach = false

    @Option(name: .long, help: "Diretório de trabalho.")
    var cwd: String?

    func run() async throws {
        let bottle = try CLI.bottle(self.bottle)
        let engine = try CLI.engine(for: bottle)

        var url = URL(fileURLWithPath: file)
        var programArguments = arguments
        var workingDirectory = cwd.map { URL(fileURLWithPath: $0, isDirectory: true) }
        var program: Program?

        if !FileManager.default.fileExists(atPath: url.path) {
            if let match = ProgramScanner.allPrograms(in: bottle).first(where: { $0.name.caseInsensitiveCompare(file) == .orderedSame }) {
                program = match
                url = match.url
                if programArguments.isEmpty { programArguments = match.argumentList }
                if workingDirectory == nil, let dir = match.workingDirectory {
                    workingDirectory = URL(fileURLWithPath: dir, isDirectory: true)
                }
            } else if let unix = WinePath.toUnix(file, bottle: bottle), FileManager.default.fileExists(atPath: unix.path) {
                url = unix
            } else {
                throw BlottleError.fileNotFound(file)
            }
        }

        let launched: LaunchedProcess
        if var program, program.kind == .steam {
            program.arguments = ArgumentSplitter.join(programArguments)
            launched = try ProgramLauncher.launch(program, in: bottle, engine: engine)
        } else {
            launched = try ProgramLauncher.launch(
                file: url,
                arguments: programArguments,
                workingDirectory: workingDirectory,
                in: bottle,
                engine: engine
            )
        }
        CLI.printProgress("rodando \(url.lastPathComponent) (pid \(launched.processIdentifier), log: \(launched.logURL.path))")
        if !detach {
            launched.process.waitUntilExit()
            let code = launched.process.terminationStatus
            if code != 0 {
                CLI.printProgress("programa terminou com código \(code)")
                throw ExitCode(code)
            }
        }
    }
}

// MARK: - steam

struct SteamCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "steam",
        abstract: "Instala e roda o cliente Steam (Windows) em uma garrafa.",
        subcommands: [Install.self, Run.self, Fix.self]
    )

    struct Install: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Baixa e instala o Steam na garrafa.")

        @Argument var bottle: String

        @Option(name: .long, help: "Preset: webHelperWrapper, cefFlags, plain.")
        var preset: String = SteamPreset.webHelperWrapper.rawValue

        @Flag(name: .long, help: "Copia a sessão de login do Steam nativo do macOS.")
        var importMacLogin = false

        @Flag(name: .long, help: "Também aplica os padrões de jogo à garrafa (MSync, D3DMetal se possível).")
        var gaming = false

        func run() async throws {
            var bottle = try CLI.bottle(self.bottle)
            let engine = try CLI.engine(for: bottle)
            guard let presetValue = SteamPreset(rawValue: preset) else {
                throw ValidationError("preset inválido: \(preset)")
            }
            var options = SteamOptions()
            options.preset = presetValue
            options.importMacLogin = importMacLogin
            if gaming {
                let gamingSettings = BottleSettings.gaming(engine: engine)
                bottle.settings.sync = gamingSettings.sync
                bottle.settings.graphics = gamingSettings.graphics
            }
            try await SteamInstaller.install(into: &bottle, engine: engine, options: options) { CLI.printProgress($0) }
            try CLI.store.save(bottle)
            print("Steam instalado. Rode com: blottle steam run \"\(bottle.name)\"")
            if presetValue == .webHelperWrapper, SteamInstaller.locateWrapper(named: SteamInstaller.wrapperFileNames[0].wrapper) == nil {
                CLI.printProgress("aviso: wrapper do steamwebhelper não encontrado; rode `make wrapper` ou copie os .exe para \(BlottlePaths.tools.path)")
            }
        }
    }

    struct Run: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Abre o Steam.")

        @Argument var bottle: String

        @Argument(parsing: .captureForPassthrough, help: "Argumentos extras para o steam.exe.")
        var arguments: [String] = []

        func run() async throws {
            let bottle = try CLI.bottle(self.bottle)
            let engine = try CLI.engine(for: bottle)
            guard var program = bottle.programs.first(where: { $0.kind == .steam }) else {
                guard SteamInstaller.isInstalled(in: bottle) else {
                    throw BlottleError.fileNotFound("Steam não está instalado nesta garrafa; use `blottle steam install`.")
                }
                let launched = try ProgramLauncher.launch(
                    SteamInstaller.program(for: bottle, options: SteamOptions()), in: bottle, engine: engine
                )
                launched.process.waitUntilExit()
                return
            }
            if !arguments.isEmpty {
                program.arguments = ArgumentSplitter.join(program.argumentList + arguments)
            }
            let launched = try ProgramLauncher.launch(program, in: bottle, engine: engine)
            CLI.printProgress("Steam rodando (log: \(launched.logURL.path))")
            launched.process.waitUntilExit()
        }
    }

    struct Fix: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Reaplica o wrapper do steamwebhelper.")

        @Argument var bottle: String

        @Option(name: .long, help: "Pasta com steamwebhelper-wrapper-x64.exe / -x86.exe.")
        var wrapperDir: String?

        func run() async throws {
            let bottle = try CLI.bottle(self.bottle)
            let applied = try SteamInstaller.applyWebHelperWrapper(
                to: bottle,
                wrapperDirectory: wrapperDir.map { URL(fileURLWithPath: $0, isDirectory: true) }
            )
            print(applied ? "Wrapper aplicado." : "Nada aplicado: o Steam ainda não baixou o CEF ou o wrapper não foi encontrado.")
        }
    }
}

// MARK: - winetricks

struct WinetricksCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "winetricks",
        abstract: "Roda verbos do winetricks em uma garrafa (ex.: corefonts vcrun2022)."
    )

    @Argument(help: "Nome da garrafa.")
    var bottle: String?

    @Argument(parsing: .remaining, help: "Verbos do winetricks.")
    var verbs: [String] = []

    @Flag(name: .long, help: "Mostra os verbos mais usados.")
    var list = false

    @Flag(name: .long, help: "Baixa a versão mais recente do script antes de rodar.")
    var update = false

    func run() async throws {
        if list {
            for item in Winetricks.popularVerbs { print("\(item.verb)\t\(item.description)") }
            return
        }
        guard let bottleReference = bottle else { throw ValidationError("informe a garrafa") }
        guard !verbs.isEmpty else { throw ValidationError("informe ao menos um verbo ou use --list") }
        let bottle = try CLI.bottle(bottleReference)
        let engine = try CLI.engine(for: bottle)
        let runner = WineRunner(engine: engine, bottle: bottle)
        let result = try await Winetricks.run(verbs: verbs, runner: runner, forceUpdate: update)
        print(result.output.split(separator: "\n").suffix(20).joined(separator: "\n"))
        guard result.succeeded else { throw ExitCode(result.exitCode) }
        print("winetricks concluído.")
    }
}

// MARK: - dxvk / d3dmetal / dxmt

struct DXVKCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dxvk",
        abstract: "Instala ou remove o DXVK (DirectX 10/11 via MoltenVK) em uma garrafa.",
        subcommands: [Install.self, Remove.self]
    )

    struct Install: AsyncParsableCommand {
        @Argument var bottle: String
        @Option(name: .long, help: "Pacote .tar.gz local em vez de baixar.") var archive: String?

        func run() async throws {
            var bottle = try CLI.bottle(self.bottle)
            let dlls = try await DXVKInstaller.install(
                into: bottle,
                archive: archive.map { URL(fileURLWithPath: $0) }
            ) { CLI.progressBar($0) }
            bottle.settings.graphics = .dxvk
            try CLI.store.save(bottle)
            print("DXVK instalado (\(dlls.joined(separator: ", "))). Backend gráfico definido para DXVK.")
        }
    }

    struct Remove: AsyncParsableCommand {
        @Argument var bottle: String

        func run() async throws {
            var bottle = try CLI.bottle(self.bottle)
            try DXVKInstaller.uninstall(from: bottle)
            if bottle.settings.graphics == .dxvk { bottle.settings.graphics = .wined3d }
            try CLI.store.save(bottle)
            print("DXVK removido.")
        }
    }
}

struct D3DMetalCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "d3dmetal",
        abstract: "Instala as bibliotecas D3DMetal da Apple (Game Porting Toolkit) em uma engine.",
        subcommands: [Install.self, Status.self]
    )

    struct Install: AsyncParsableCommand {
        @Argument(help: "Id da engine (GPTK/WhiskyWine).") var engine: String
        @Argument(help: "Caminho do .dmg do Game Porting Toolkit (ou pasta com lib/external).", completion: .file()) var source: String

        func run() async throws {
            let engine = try CLI.engine(self.engine)
            try await D3DMetalInstaller.install(from: URL(fileURLWithPath: source), into: engine)
            print("D3DMetal instalado em \(engine.externalLibDirectory.path)")
        }
    }

    struct Status: AsyncParsableCommand {
        func run() async throws {
            print("macOS \(SystemInfo.macOSVersionString), \(SystemInfo.machineArchitecture)")
            print("Suporte a D3DMetal no sistema: \(SystemInfo.supportsD3DMetal ? "sim" : "não (requer Apple Silicon + macOS 14)")")
            for engine in CLI.engines.installed() {
                let state = engine.hasD3DMetal ? "instalado" : (engine.supportsD3DMetal ? "faltam as libs da Apple" : "engine não suporta")
                print("\(engine.id): \(state)")
            }
            print("Download do GPTK: \(D3DMetalInstaller.appleDownloadPage.absoluteString)")
        }
    }
}

struct DXMTCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dxmt",
        abstract: "Instala um pacote DXMT (experimental) em uma garrafa."
    )

    @Argument var bottle: String
    @Argument(help: "Pacote .tar.gz do DXMT.", completion: .file()) var archive: String

    func run() async throws {
        var bottle = try CLI.bottle(self.bottle)
        let engine = try CLI.engine(for: bottle)
        let files = try await DXMTInstaller.install(archive: URL(fileURLWithPath: archive), into: bottle, engine: engine)
        bottle.settings.graphics = .dxmt
        try CLI.store.save(bottle)
        print("DXMT instalado (\(files.joined(separator: ", "))).")
    }
}

// MARK: - doctor

struct DoctorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Verifica se o Mac está pronto para rodar Wine."
    )

    func run() async throws {
        func line(_ ok: Bool, _ text: String) { print("\(ok ? "✓" : "✗") \(text)") }

        print("macOS \(SystemInfo.macOSVersionString) em \(SystemInfo.machineArchitecture)")
        line(SystemInfo.macOSVersion.majorVersion >= 14, "macOS 14 Sonoma ou mais recente")
        if SystemInfo.isAppleSilicon {
            line(SystemInfo.isRosettaInstalled, "Rosetta 2 instalado (senão: \(SystemInfo.rosettaInstallCommand))")
        } else {
            print("• Mac Intel: Rosetta não é necessário; D3DMetal não está disponível.")
        }
        line(SystemInfo.homebrewPrefix != nil, "Homebrew encontrado (para cabextract/winetricks)")
        line(ProcessRunner.which("cabextract") != nil, "cabextract instalado (brew install cabextract)")

        let engines = CLI.engines.installed()
        line(!engines.isEmpty, "\(engines.count) engine(s) instalada(s)")
        for engine in engines {
            let version = await WineEngine.probeVersion(wineBinary: engine.wineBinary)
            line(!version.isEmpty, "\(engine.id): \(version.isEmpty ? "wine não executa" : version)")
        }
        let bottles = CLI.store.list()
        print("• \(bottles.count) garrafa(s) em \(BlottlePaths.bottles.path)")
        let wrapper = SteamInstaller.locateWrapper(named: SteamInstaller.wrapperFileNames[0].wrapper)
        line(wrapper != nil, "wrapper do steamwebhelper \(wrapper.map { "em \($0.path)" } ?? "não encontrado (make wrapper)")")
    }
}
