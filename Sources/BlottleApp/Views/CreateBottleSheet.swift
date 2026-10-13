import BlottleKit
import SwiftUI

struct CreateBottleSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var engineID = ""
    @State private var windowsVersion: WindowsVersion = .win10
    @State private var gaming = true

    private var engine: WineEngine? { model.engines.first { $0.id == engineID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nova garrafa").font(.title2)
            Form {
                TextField("Nome", text: $name, prompt: Text("Jogos, Office, Steam…"))
                Picker("Engine Wine", selection: $engineID) {
                    ForEach(model.engines) { engine in
                        Text("\(engine.name) (\(engine.displayVersion))").tag(engine.id)
                    }
                }
                Picker("Versão do Windows", selection: $windowsVersion) {
                    ForEach(WindowsVersion.allCases, id: \.self) { version in
                        Text(version.displayName).tag(version)
                    }
                }
                Toggle("Otimizar para jogos (MSync, D3DMetal quando disponível)", isOn: $gaming)
                if let engine, gaming {
                    if engine.supportsD3DMetal, !engine.hasD3DMetal {
                        Text("Esta engine aceita D3DMetal, mas as bibliotecas da Apple ainda não foram instaladas (Ajustes › Engines).")
                            .font(.caption).foregroundStyle(.orange)
                    } else if !engine.supportsD3DMetal {
                        Text("Engine sem D3DMetal: jogos DirectX 11 usam WineD3D (lento) ou DXVK (instale depois em Configurar).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            if model.engines.isEmpty {
                Text("Nenhuma engine instalada. Abra Ajustes › Engines para baixar uma.")
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Criar") {
                    guard let engine else { return }
                    var settings = gaming ? BottleSettings.gaming(engine: engine) : BottleSettings()
                    settings.windowsVersion = windowsVersion
                    model.createBottle(name: name, engine: engine, settings: settings)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || engine == nil)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            if engineID.isEmpty { engineID = model.engines.first?.id ?? "" }
        }
    }
}
