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

        WindowGroup("Diff", for: GitCommitDiffSheetItem.self) { $item in
            if let item {
                GitCommitDiffWindow(item: item)
                    .environment(appState)
                    .environment(workspaceStore)
            }
        }
        .defaultSize(width: 1100, height: 700)
        .restorationBehavior(.disabled)

        Window("About SwiftTerminal", id: "about") {
            AboutView()
                .containerBackground(.regularMaterial, for: .window)
                .toolbar(removing: .title)
                .toolbarBackground(.hidden, for: .windowToolbar)
                .windowMinimizeBehavior(.disabled)
        }
        .windowBackgroundDragBehavior(.enabled)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView()
                .environment(updater)
        }
    }
}
