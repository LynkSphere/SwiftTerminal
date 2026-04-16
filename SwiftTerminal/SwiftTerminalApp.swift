import SwiftUI

@main
struct SwiftTerminalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var workspaceStore = WorkspaceStore()
    @State private var appState = AppState()
    @State private var updater = UpdaterManager()

    var body: some Scene {
        Window("SwiftTerminal", id: "swiftterminal") {
            ContentView()
                .environment(appState)
                .environment(workspaceStore)
                .frame(minWidth: 600, minHeight: 400)
        }
        .defaultSize(width: 900, height: 600)
        .commands {
            AppCommands(appState: appState, updater: updater)
        }

        WindowGroup("Editor", for: EditorPanelContent.self) { $content in
            if let content {
                DetachedEditorView(content: content)
                    .frame(minWidth: 400, minHeight: 300)
            }
        }
        .defaultSize(width: 875, height: 625)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView()
                .environment(updater)
        }
    }
}
