import BlottleKit
import SwiftUI

struct WinetricksSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let bottle: Bottle
    @State private var selected: Set<String> = []
    @State private var custom = ""

    private var verbs: [String] {
        Winetricks.popularVerbs.map(\.verb).filter { selected.contains($0) } + ArgumentSplitter.split(custom)
    }

    private var missing: [String] { Winetricks.missingDependencies() }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Winetricks em \(bottle.name)").font(.title2)
            Text("Instala componentes do Windows que muitos programas exigem.")
                .foregroundStyle(.secondary)
            if !missing.isEmpty {
                Label("Instale primeiro: brew install \(missing.joined(separator: " "))", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            List {
                ForEach(Winetricks.popularVerbs, id: \.verb) { item in
                    Toggle(isOn: Binding(
                        get: { selected.contains(item.verb) },
                        set: { on in if on { selected.insert(item.verb) } else { selected.remove(item.verb) } }
                    )) {
                        VStack(alignment: .leading) {
                            Text(item.verb).font(.body.monospaced())
                            Text(item.description).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(minHeight: 260)
            TextField("Outros verbos (separados por espaço)", text: $custom, prompt: Text("dotnet6 faudio"))
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Executar") {
                    model.runWinetricks(verbs, in: bottle)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(verbs.isEmpty || !missing.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}
