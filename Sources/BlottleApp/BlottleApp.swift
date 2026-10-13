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

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // When started straight from `swift run` there is no bundle, so make
        // sure we still get a Dock icon and keyboard focus.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
