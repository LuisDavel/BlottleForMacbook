import BlottleKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct BottleDetailView: View {
    @Environment(AppModel.self) private var model
    let bottle: Bottle

    @State private var showConfig = false
    @State private var showSteam = false
    @State private var showWinetricks = false
    @State private var showLogs = false
    @State private var showDeleteConfirmation = false
    @State private var isDropTargeted = false
    @State private var editingProgram: Program?

    private var engine: WineEngine? { model.engine(for: bottle) }
    private var programs: [Program] { model.programs(for: bottle) }
    private var steamInstalled: Bool { SteamInstaller.isInstalled(in: bottle) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            programList
        }
        .navigationTitle(bottle.name)
        .navigationSubtitle(engine.map { "\($0.name) · \($0.displayVersion)" } ?? "engine ausente")
        .toolbar { toolbarContent }
        .sheet(isPresented: $showConfig) { BottleConfigView(bottle: bottle) }
        .sheet(isPresented: $showSteam) { SteamSheet(bottle: bottle) }
        .sheet(isPresented: $showWinetricks) { WinetricksSheet(bottle: bottle) }
        .sheet(isPresented: $showLogs) { LogView(bottle: bottle) }
        .sheet(item: $editingProgram) { program in ProgramEditorSheet(bottle: bottle, program: program) }
        .confirmationDialog(
            "Apagar a garrafa \"\(bottle.name)\"?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Apagar", role: .destructive) { model.deleteBottle(bottle) }
        } message: {
            Text("Todos os programas e jogos instalados nela serão removidos. Isso não pode ser desfeito.")
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .task(id: bottle.id) {
            await model.refreshPrograms(for: bottle)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    chip(bottle.settings.windowsVersion.displayName, systemImage: "pc")
                    chip(bottle.settings.graphics.displayName, systemImage: "cpu")
                    chip(bottle.settings.sync.displayName, systemImage: "arrow.triangle.2.circlepath")
                    if DXVKInstaller.isInstalled(in: bottle) {
                        chip("DXVK instalado", systemImage: "checkmark.seal")
                    }
                }
                Text(bottle.url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            HStack(spacing: 8) {
                Button {
                    model.openRunPanel(for: bottle)
                } label: {
                    Label("Executar arquivo…", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .help("Abre um .exe, .msi, .bat ou .lnk nesta garrafa")

                if steamInstalled {
                    Button {
                        if let steam = bottle.programs.first(where: { $0.kind == .steam }) {
                            model.launch(steam, in: bottle)
                        } else {
                            model.launch(SteamInstaller.program(for: bottle, options: SteamOptions()), in: bottle)
                        }
                    } label: {
                        Label("Abrir Steam", systemImage: "gamecontroller")
                    }
                } else {
                    Button {
                        showSteam = true
                    } label: {
                        Label("Instalar Steam", systemImage: "gamecontroller")
                    }
                }
            }
        }
        .padding(16)
    }

    private func chip(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.12), in: Capsule())
    }

    // MARK: - Programs

    private var programList: some View {
        Group {
            if programs.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.down.on.square")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Arraste um .exe para cá ou clique em \"Executar arquivo…\"")
                        .foregroundStyle(.secondary)
                    Text("Instaladores (.msi/.exe) rodam normalmente; os programas instalados aparecem aqui.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Program.Source.allCases, id: \.self) { source in
                        let items = programs.filter { $0.source == source }
                        if !items.isEmpty {
                            Section(sectionTitle(for: source)) {
                                ForEach(items) { program in
                                    ProgramRow(bottle: bottle, program: program) {
                                        editingProgram = program
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func sectionTitle(for source: Program.Source) -> String {
        switch source {
        case .pinned: return "Favoritos"
        case .startMenu: return "Menu Iniciar"
        case .scanned: return "Encontrados em Program Files"
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { showConfig = true } label: { Label("Configurar", systemImage: "slider.horizontal.3") }
                .help("Versão do Windows, gráficos, variáveis…")
            Button { showWinetricks = true } label: { Label("Winetricks", systemImage: "wand.and.stars") }
                .help("Instalar fontes, Visual C++, .NET…")
            Menu {
                ForEach(WineTool.allCases) { tool in
                    Button(tool.title) { model.open(tool, in: bottle) }
                }
                Divider()
                Button("Abrir unidade C: no Finder") { model.openCDrive(bottle) }
                Button("Abrir pasta de logs") { model.openLogsFolder(bottle) }
                Button("Ver logs") { showLogs = true }
                Divider()
                Button("Encerrar todos os processos") { model.killAll(in: bottle) }
                Button("Apagar garrafa…", role: .destructive) { showDeleteConfirmation = true }
            } label: {
                Label("Ferramentas", systemImage: "wrench.and.screwdriver")
            }
            Button {
                Task { await model.refreshPrograms(for: bottle) }
            } label: {
                Label("Atualizar lista", systemImage: "arrow.clockwise")
            }
        }
    }

    // MARK: - Drop

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            handled = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let direct = item as? URL {
                    url = direct
                }
                guard let url else { return }
                Task { @MainActor in
                    model.launchFile(url, in: bottle)
                }
            }
        }
        return handled
    }
}

@MainActor
struct ProgramRow: View {
    @Environment(AppModel.self) private var model
    let bottle: Bottle
    let program: Program
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: program.kind == .steam ? "gamecontroller.fill" : "app.fill")
                .font(.title2)
                .foregroundStyle(program.kind == .steam ? Color.blue : Color.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(program.name).fontWeight(.medium)
                Text(WinePath.toWindows(program.url, bottle: bottle) ?? program.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !program.arguments.isEmpty {
                    Text("Argumentos: \(program.arguments)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if !program.exists {
                Text("arquivo ausente").font(.caption).foregroundStyle(.red)
            }
            Button {
                model.launch(program, in: bottle)
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.borderless)
            .disabled(!program.exists)
            .help("Executar")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if program.exists { model.launch(program, in: bottle) }
        }
        .contextMenu {
            Button("Executar") { model.launch(program, in: bottle) }
            Button("Editar argumentos…") { onEdit() }
            if program.source == .pinned {
                Button("Remover dos favoritos") { model.unpin(program, in: bottle) }
            } else {
                Button("Adicionar aos favoritos") { model.pin(program, in: bottle) }
            }
            Divider()
            Button("Mostrar no Finder") { model.revealInFinder(program.url) }
        }
    }
}

@MainActor
struct ProgramEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let bottle: Bottle
    @State var program: Program
    @State private var environmentText: String

    init(bottle: Bottle, program: Program) {
        self.bottle = bottle
        _program = State(initialValue: program)
        _environmentText = State(initialValue: program.environment
            .map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "\n"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Editar \(program.name)").font(.title2)
            Form {
                TextField("Nome", text: $program.name)
                TextField("Argumentos", text: $program.arguments, prompt: Text("-windowed -novid"))
                TextField("Diretório de trabalho", text: Binding(
                    get: { program.workingDirectory ?? "" },
                    set: { program.workingDirectory = $0.isEmpty ? nil : $0 }
                ))
                VStack(alignment: .leading) {
                    Text("Variáveis de ambiente (uma por linha, CHAVE=VALOR)")
                    TextEditor(text: $environmentText)
                        .font(.body.monospaced())
                        .frame(minHeight: 80)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Salvar") {
                    var updated = program
                    updated.source = .pinned
                    updated.environment = Self.parseEnvironment(environmentText)
                    model.updateProgram(updated, in: bottle)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    static func parseEnvironment(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, !parts[0].isEmpty else { continue }
            result[parts[0]] = parts[1]
        }
        return result
    }
}
