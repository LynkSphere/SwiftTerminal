import SwiftUI
import SwiftData

@main
struct SwiftTerminalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    let container: ModelContainer
    @State private var appState = AppState()

    init() {
        self.container = try! ModelContainer(for: Workspace.self)
    }

    var body: some Scene {
        Window("main", id: "main") {
            ContentView()
                .environment(appState)
                .modelContainer(container)
                .frame(minWidth: 600, minHeight: 400)
        }
        .defaultSize(width: 900, height: 600)
        .commands {
            AppCommands(appState: appState)
        }

        WindowGroup("Editor", for: EditorPanelContent.self) { $content in
            if let content {
                DetachedEditorView(content: content)
                    .frame(minWidth: 400, minHeight: 300)
            }
        }
        .defaultSize(width: 700, height: 500)
        .restorationBehavior(.disabled)
    }
}
