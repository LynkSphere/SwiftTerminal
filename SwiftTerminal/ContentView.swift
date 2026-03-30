import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Query private var workspaces: [Workspace]
    @State private var editorPanel = EditorPanel()
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            WorkspaceListView(searchText: searchText)
                .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 300)
                .searchable(text: $searchText, placement: .sidebar, prompt: "Filter workspaces")
        } detail: {
            if let workspace = appState.selectedWorkspace {
                WorkspaceDetailView(workspace: workspace)
                    .id(workspace.id)
            } else {
                ContentUnavailableView(
                    "No Workspace Selected",
                    systemImage: "sidebar.left",
                    description: Text("Select a workspace to get started.")
                )
            }
        }
        .inspector(isPresented: Bindable(appState).showingInspector) {
            if let workspace = appState.selectedWorkspace {
                InspectorView(directoryURL: workspace.url)
                    .inspectorColumnWidth(min: 240, ideal: 240, max: 360)
            }
        }
        .environment(editorPanel)
        .focusedSceneValue(\.editorPanel, editorPanel)
        .onReceive(NotificationCenter.default.publisher(for: .navigateToSession)) { notification in
            guard let workspaceID = notification.userInfo?["workspaceID"] as? String,
                  let terminalID = notification.userInfo?["terminalID"] as? String else { return }

            if let workspace = workspaces.first(where: { $0.id.uuidString == workspaceID }) {
                appState.selectedWorkspace = workspace
                if let terminal = workspace.terminals.first(where: { $0.id.uuidString == terminalID }) {
                    appState.selectedTerminal = terminal
                }
            }
        }
    }
}
