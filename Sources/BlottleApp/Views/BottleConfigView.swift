import BlottleKit
import SwiftUI

@MainActor
struct BottleConfigView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let bottle: Bottle
    @State private var settings: BottleSettings
    @State private var engineID: String
    @State private var environmentText: String
    @State private var overridesText: String

    init(bottle: Bottle) {
        self.bottle = bottle
        _settings = State(initialValue: bottle.settings)
        _engineID = State(initialValue: bottle.engineID)
        _environmentText = State(initialValue: bottle.settings.environment
            .map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "\n"))
        _overridesText = State(initialValue: bottle.settings.dllOverrides
            .map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "\n"))
    }

    private var engine: WineEngine? { model.engines.first { $0.id == engineID } }
    private var dxvkInstalled: Bool { model.status(for: bottle).dxvkInstalled }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Configurar \(bottle.name)").font(.title2)
                Spacer()
            }
            .padding(20)

            TabView {
                generalTab.tabItem { Text("Geral") }
                graphicsTab.tabItem { Text("Gráficos") }
                advancedTab.tabItem { Text("Avançado") }
            }
            .padding(.horizontal, 20)

            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Salvar") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .frame(width: 620, height: 560)
    }

    private var generalTab: some View {
        Form {
            Picker("Engine Wine", selection: $engineID) {
                ForEach(model.engines) { engine in
                    Text("\(engine.name) (\(engine.displayVersion))").tag(engine.id)
                }
            }
            Picker("Versão do Windows", selection: $settings.windowsVersion) {
                ForEach(WindowsVersion.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Picker("Sincronização", selection: $settings.sync) {
                ForEach(SyncMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Toggle("Modo Retina (renderiza em alta resolução; textos ficam pequenos)", isOn: $settings.retinaMode)
            Stepper("DPI: \(settings.dpi) (\(settings.dpi * 100 / 96)%)", value: $settings.dpi, in: 72...288, step: 24)
            Toggle("Anunciar AVX ao Rosetta (jogos que exigem AVX)", isOn: $settings.advertiseAVX)
        }
        .formStyle(.grouped)
    }

    private var graphicsTab: some View {
        Form {
            Picker("Backend Direct3D", selection: $settings.graphics) {
                ForEach(GraphicsBackend.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            switch settings.graphics {
            case .d3dmetal:
                if let engine {
                    if engine.hasD3DMetal {
                        Label("D3DMetal pronto nesta engine.", systemImage: "checkmark.circle").foregroundStyle(.green)
                    } else if engine.supportsD3DMetal {
                        Label("Faltam as bibliotecas da Apple: instale em Ajustes › Engines.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    } else {
                        Label("A engine \(engine.name) não é baseada no GPTK; D3DMetal não vai funcionar.", systemImage: "xmark.octagon")
                            .foregroundStyle(.red)
                    }
                }
                Toggle("Suporte a DirectX Raytracing (D3DM_SUPPORT_DXR)", isOn: $settings.dxrEnabled)
            case .dxvk:
                HStack {
                    if dxvkInstalled {
                        Label("DXVK instalado nesta garrafa.", systemImage: "checkmark.circle").foregroundStyle(.green)
                        Spacer()
                        Button("Remover DXVK") { model.removeDXVK(in: bottle); dismiss() }
                    } else {
                        Label("As DLLs do DXVK ainda não foram instaladas.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Instalar DXVK") { model.installDXVK(in: bottle); dismiss() }
                    }
                }
                Toggle("DXVK assíncrono (menos travadas ao compilar shaders)", isOn: $settings.dxvkAsync)
                Picker("HUD do DXVK", selection: $settings.dxvkHUD) {
                    ForEach(DXVKHUD.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            case .dxmt:
                HStack {
                    Text("DXMT é experimental. Baixe um pacote em github.com/3Shain/dxmt e instale aqui.")
                        .font(.caption)
                    Spacer()
                    Button("Instalar pacote DXMT…") { model.installDXMTPanel(in: bottle); dismiss() }
                }
            case .wined3d:
                Text("WineD3D traduz Direct3D para OpenGL. Funciona em tudo, mas é o mais lento para jogos.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle("HUD de desempenho do Metal (FPS)", isOn: $settings.metalHUD)
            Toggle("Captura do Metal (METAL_CAPTURE_ENABLED, só para depuração)", isOn: $settings.metalTrace)
        }
        .formStyle(.grouped)
    }

    private var advancedTab: some View {
        Form {
            TextField("WINEDEBUG", text: $settings.wineDebug, prompt: Text("fixme-all"))
            Toggle("Reaplicar wrapper do steamwebhelper ao abrir o Steam", isOn: $settings.steamWebHelperFix)
            Section("Variáveis de ambiente (CHAVE=VALOR por linha)") {
                TextEditor(text: $environmentText)
                    .font(.body.monospaced())
                    .frame(minHeight: 90)
            }
            Section("Overrides de DLL (dll=n,b por linha)") {
                TextEditor(text: $overridesText)
                    .font(.body.monospaced())
                    .frame(minHeight: 70)
            }
        }
        .formStyle(.grouped)
    }

    private func save() {
        var updated = bottle
        updated.engineID = engineID
        var newSettings = settings
        newSettings.environment = ProgramEditorSheet.parseEnvironment(environmentText)
        newSettings.dllOverrides = ProgramEditorSheet.parseEnvironment(overridesText)
        updated.settings = newSettings
        let registryChanged = bottle.settings.windowsVersion != newSettings.windowsVersion
            || bottle.settings.retinaMode != newSettings.retinaMode
            || bottle.settings.dpi != newSettings.dpi
            || bottle.engineID != engineID
        model.save(updated, applyRegistry: registryChanged)
        dismiss()
    }
}
