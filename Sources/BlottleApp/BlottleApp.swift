import AppKit
import BlottleKit
import SwiftUI

@main
struct BlottleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 560)
                .onAppear { appDelegate.model = model }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Nova garrafa…") { model.showCreateBottle = true }
                    .keyboardShortcut("n", modifiers: [.command])
            }
            CommandGroup(after: .newItem) {
                Button("Executar arquivo Windows…") {
                    if let bottle = model.selectedBottle { model.openRunPanel(for: bottle) }
                }
                .keyboardShortcut("o", modifiers: [.command])
                .disabled(model.selectedBottle == nil)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
                .frame(width: 720, height: 520)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by `BlottleApp` once the main window appears.
    var model: AppModel?

    private var runningCount: Int {
        model?.running.filter { $0.process.isRunning }.count ?? 0
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // When started straight from `swift run` there is no bundle, so make
        // sure we still get a Dock icon and keyboard focus.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        runningCount == 0
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let count = runningCount
        guard count > 0 else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Há \(count) programa(s) em execução. Sair mesmo assim?"
        alert.informativeText = "Os programas continuam rodando em segundo plano."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Sair")
        alert.addButton(withTitle: "Cancelar")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        true
    }
}
