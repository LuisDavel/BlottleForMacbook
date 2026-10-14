import BlottleKit
import SwiftUI

@MainActor
struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selectedBottleID) {
                Section("Garrafas") {
                    ForEach(model.bottles) { bottle in
                        BottleRow(bottle: bottle)
                            .tag(bottle.id)
                            .contextMenu {
                                Button("Abrir unidade C: no Finder") { model.openCDrive(bottle) }
                                Button("Encerrar processos") { model.killAll(in: bottle) }
                                Divider()
                                Button("Apagar garrafa…", role: .destructive) { model.deleteBottle(bottle) }
                            }
                    }
                }
                if !model.running.isEmpty {
                    Section("Em execução") {
                        ForEach(model.running) { item in
                            HStack {
                                Image(systemName: "circle.fill").foregroundStyle(.green).font(.caption2)
                                Text(item.name).lineLimit(1)
                                Spacer()
                                Button {
                                    item.process.terminate()
                                    model.pruneRunning()
                                } label: {
                                    Image(systemName: "stop.circle")
                                }
                                .buttonStyle(.plain)
                                .help("Encerrar")
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        model.showCreateBottle = true
                    } label: {
                        Label("Nova garrafa", systemImage: "plus")
                    }
                    .help("Criar uma garrafa nova")
                }
            }
        } detail: {
            if let bottle = model.selectedBottle {
                BottleDetailView(bottle: bottle)
                    .id(bottle.id)
            } else {
                EmptyStateView()
            }
        }
        .sheet(isPresented: $model.showCreateBottle) {
            CreateBottleSheet()
        }
        .alert(
            model.alert?.title ?? "",
            isPresented: Binding(
                get: { model.alert != nil },
                set: { if !$0 { model.alert = nil } }
            ),
            presenting: model.alert
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { info in
            Text(info.message)
        }
        .overlay {
            if let busy = model.busy {
                BusyOverlay(state: busy) { model.cancelBusy() }
            }
        }
    }
}

@MainActor
struct BottleRow: View {
    @Environment(AppModel.self) private var model
    let bottle: Bottle

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(bottle.name)
                Text(bottle.settings.windowsVersion.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: model.status(for: bottle).steamInstalled ? "gamecontroller.fill" : "cylinder.fill")
        }
    }
}

@MainActor
struct EmptyStateView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cylinder.split.1x2")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Nenhuma garrafa selecionada")
                .font(.title2)
            Text("Uma garrafa é um Windows virtual onde seus programas e jogos são instalados.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            if model.engines.isEmpty {
                Text("Primeiro instale uma engine Wine em Ajustes › Engines (⌘,).")
                    .foregroundStyle(.orange)
                SettingsLink {
                    Text("Abrir Ajustes")
                }
            } else {
                Button("Criar garrafa") { model.showCreateBottle = true }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}

@MainActor
struct BusyOverlay: View {
    let state: BusyState
    var onCancel: () -> Void = {}

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 12) {
                if let progress = state.progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(width: 260)
                } else {
                    ProgressView()
                }
                Text(state.title).font(.headline)
                if !state.detail.isEmpty {
                    Text(state.detail).font(.caption).foregroundStyle(.secondary)
                }
                if state.cancellable {
                    Button("Cancelar") { onCancel() }
                        .keyboardShortcut(.cancelAction)
                        .padding(.top, 4)
                }
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}
