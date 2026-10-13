import BlottleKit
import SwiftUI

@MainActor
struct CreateBottleSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var engineID = ""
    @State private var windowsVersion: WindowsVersion = .win10
    @State private var gaming = true
    @State private var location: URL?

    private var engine: WineEngine? { model.engines.first { $0.id == engineID } }

    private var locationDescription: String {
        guard let location else { return "Padrão (Application Support/Blottle/Bottles)" }
        return location.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private var externalVolumeName: String? {
        guard let location,
              let values = try? location.resourceValues(forKeys: [.volumeIsInternalKey, .volumeNameKey]),
              values.volumeIsInternal == false else { return nil }
        return values.volumeName
    }

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
                LabeledContent("Local") {
                    HStack {
                        Text(locationDescription)
                            .lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(location == nil ? .secondary : .primary)
                            .help((location ?? model.store.directory).path)
                        Spacer()
                        if location != nil {
                            Button("Padrão") { location = nil }
                        }
                        Button("Escolher…") {
                            if let url = model.chooseBottleLocationPanel() { location = url }
                        }
                    }
                }
                if let volume = externalVolumeName {
                    Text("Os programas desta garrafa serão instalados no disco \"\(volume)\". Se ele for desconectado, a garrafa some da lista até voltar.")
                        .font(.caption).foregroundStyle(.secondary)
                }
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
                    model.createBottle(name: name, engine: engine, settings: settings, location: location)
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
