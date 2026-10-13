import BlottleKit
import SwiftUI

struct SteamSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let bottle: Bottle
    @State private var preset: SteamPreset = .webHelperWrapper
    @State private var importMacLogin = false
    @State private var gaming = true
    @State private var extraArguments = ""

    private var wrapperAvailable: Bool {
        SteamInstaller.locateWrapper(named: SteamInstaller.wrapperFileNames[0].wrapper) != nil
    }

    private var macSteamPresent: Bool {
        FileManager.default.fileExists(atPath: SteamInstaller.macSteamDirectory.appendingPathComponent("config").path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Instalar Steam em \(bottle.name)").font(.title2)
            Text("O instalador oficial do Steam para Windows será baixado e executado nesta garrafa. Na primeira abertura o Steam baixa o cliente completo (alguns minutos).")
                .font(.callout)
                .foregroundStyle(.secondary)

            Form {
                Picker("Correção do CEF", selection: $preset) {
                    ForEach(SteamPreset.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                if preset == .webHelperWrapper {
                    if wrapperAvailable {
                        Label("Wrapper do steamwebhelper encontrado.", systemImage: "checkmark.circle").foregroundStyle(.green)
                    } else {
                        Label("Wrapper não encontrado: rode `make wrapper` ou copie os .exe para \(BlottlePaths.tools.path). Sem ele, a janela do Steam pode ficar preta.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                Text("Argumentos: \(ArgumentSplitter.join(preset.arguments + ArgumentSplitter.split(extraArguments)))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                TextField("Argumentos extras", text: $extraArguments, prompt: Text("-silent"))
                Toggle("Importar login do Steam nativo do macOS (contorna a tela de login quebrada)", isOn: $importMacLogin)
                    .disabled(!macSteamPresent)
                Toggle("Aplicar padrões de jogo à garrafa (MSync + D3DMetal se disponível)", isOn: $gaming)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Instalar") {
                    var options = SteamOptions()
                    options.preset = preset
                    options.importMacLogin = importMacLogin
                    options.extraArguments = ArgumentSplitter.split(extraArguments)
                    model.installSteam(in: bottle, options: options, gaming: gaming)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}
