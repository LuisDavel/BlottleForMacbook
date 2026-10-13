import BlottleKit
import SwiftUI

@MainActor
struct LogView: View {
    @Environment(\.dismiss) private var dismiss
    let bottle: Bottle

    @State private var files: [URL] = []
    @State private var selected: URL?
    @State private var content = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Logs de \(bottle.name)").font(.title2)
                Spacer()
                Button("Atualizar") { reload() }
                Button("Fechar") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HSplitView {
                List(files, id: \.self, selection: $selected) { file in
                    Text(file.lastPathComponent).lineLimit(1).truncationMode(.middle)
                }
                .frame(minWidth: 200, maxWidth: 280)
                ScrollView {
                    Text(content.isEmpty ? "Selecione um log." : content)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .padding(16)
        .frame(width: 820, height: 520)
        .onAppear { reload() }
        .onChange(of: selected) { _, newValue in
            load(newValue)
        }
    }

    private func reload() {
        files = BlottleLog.recent(bottle: bottle.name, limit: 50)
        if selected == nil || !files.contains(selected!) {
            selected = files.first
        }
        load(selected)
    }

    private func load(_ url: URL?) {
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else {
            content = ""
            return
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        content = lines.suffix(2000).joined(separator: "\n")
    }
}
