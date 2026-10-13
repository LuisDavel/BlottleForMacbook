import BlottleKit
import SwiftUI

@MainActor
struct SettingsView: View {
    var body: some View {
        TabView {
            EnginesSettingsView()
                .tabItem { Label("Engines", systemImage: "cpu") }
            SystemSettingsView()
                .tabItem { Label("Sistema", systemImage: "stethoscope") }
            AboutView()
                .tabItem { Label("Sobre", systemImage: "info.circle") }
        }
    }
}

@MainActor
struct EnginesSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Engines instaladas").font(.headline)
            if model.engines.isEmpty {
                Text("Nenhuma. Baixe uma do catálogo abaixo ou importe um Wine existente.")
                    .foregroundStyle(.secondary)
            }
            List {
                ForEach(model.engines) { engine in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(engine.name) · \(engine.displayVersion)").fontWeight(.medium)
                            Text("\(engine.flavor.displayName) — \(engine.root.path)")
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        if engine.hasD3DMetal {
                            Label("D3DMetal", systemImage: "checkmark.seal.fill").foregroundStyle(.green).font(.caption)
                        } else if engine.supportsD3DMetal {
                            Button("Instalar D3DMetal…") { model.installD3DMetalPanel(into: engine) }
                                .help("Escolha o .dmg do Game Porting Toolkit baixado em developer.apple.com")
                        }
                        Button(role: .destructive) {
                            model.removeEngine(engine)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Remover engine")
                    }
                }
            }
            .frame(minHeight: 120)

            HStack {
                Button("Importar Wine existente…") { model.importEnginePanel() }
                Menu("Detectar no sistema") {
                    let candidates = EngineManager.systemCandidates()
                    if candidates.isEmpty {
                        Text("Nenhum Wine conhecido encontrado")
                    }
                    ForEach(candidates, id: \.self) { candidate in
                        Button("\(candidate.name) — \(candidate.flavor.displayName)") {
                            model.importEngine(from: candidate.url, flavor: candidate.flavor)
                        }
                    }
                }
                .fixedSize()
            }

            Divider()
            Text("Catálogo").font(.headline)
            List {
                ForEach(model.catalog) { entry in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(entry.name).fontWeight(.medium)
                                if entry.status != .stable {
                                    Text(entry.status == .experimental ? "experimental" : "pode estar offline")
                                        .font(.caption2)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.2), in: Capsule())
                                }
                            }
                            Text(entry.notes).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.engines.contains(where: { $0.id == entry.id }) {
                            Text("instalada").foregroundStyle(.secondary).font(.caption)
                        } else {
                            Button("Instalar") { model.installEngine(entry) }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .frame(minHeight: 140)
        }
        .padding(20)
        .task { await model.fetchRemoteCatalog() }
    }
}

@MainActor
struct SystemSettingsView: View {
    private var checks: [(ok: Bool, text: String)] {
        var items: [(Bool, String)] = []
        items.append((SystemInfo.macOSVersion.majorVersion >= 14, "macOS \(SystemInfo.macOSVersionString) (recomendado 14 Sonoma ou mais recente)"))
        if SystemInfo.isAppleSilicon {
            items.append((SystemInfo.isRosettaInstalled, "Rosetta 2 instalado — necessário para o Wine x86_64. Instale com: \(SystemInfo.rosettaInstallCommand)"))
            items.append((SystemInfo.supportsD3DMetal, "D3DMetal disponível (Apple Silicon + macOS 14)"))
        } else {
            items.append((true, "Mac Intel: Rosetta não é necessário; D3DMetal não está disponível, use DXVK."))
        }
        items.append((SystemInfo.homebrewPrefix != nil, "Homebrew instalado (para cabextract/winetricks)"))
        items.append((ProcessRunner.which("cabextract") != nil, "cabextract instalado (brew install cabextract)"))
        let wrapper = SteamInstaller.locateWrapper(named: SteamInstaller.wrapperFileNames[0].wrapper)
        items.append((wrapper != nil, "Wrapper do steamwebhelper " + (wrapper.map { "em \($0.path)" } ?? "não encontrado (make wrapper)")))
        return items.map { (ok: $0.0, text: $0.1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Verificação do sistema").font(.headline)
            ForEach(Array(checks.enumerated()), id: \.offset) { _, check in
                Label {
                    Text(check.text).textSelection(.enabled)
                } icon: {
                    Image(systemName: check.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(check.ok ? Color.green : Color.red)
                }
            }
            Divider()
            Text("Pastas").font(.headline)
            Text("Garrafas: \(BlottlePaths.bottles.path)").font(.caption).textSelection(.enabled)
            Text("Engines: \(BlottlePaths.engines.path)").font(.caption).textSelection(.enabled)
            Text("Logs: \(BlottlePaths.logs.path)").font(.caption).textSelection(.enabled)
            Spacer()
        }
        .padding(20)
    }
}

@MainActor
struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "cylinder.split.1x2.fill").font(.system(size: 48))
            Text("Blottle").font(.title)
            Text("Rode programas Windows e jogos da Steam no seu Mac, usando Wine, D3DMetal e DXVK.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("Código aberto sob licença MIT. Wine é © WineHQ (LGPL). D3DMetal é © Apple e não é distribuído com o app.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
        }
        .padding(30)
    }
}
