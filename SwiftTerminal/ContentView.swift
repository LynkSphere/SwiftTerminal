import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationSplitView {
            WorkspaceList()
                .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 300)
        } detail: {
            if let workspace = appState.selectedWorkspace {
                WorkspaceDetailView(workspace: workspace)
                    .id(workspace.id)
            } else {
                ContentUnavailableView(
                    "No Workspace Selected",
                    systemImage: "sidebar.left",
                    description: Text("Select or create a workspace to get started.")
                )
            }
        }
        .alert("Close Tab?", isPresented: Binding(
            get: { appState.showCloseConfirmation },
            set: { appState.showCloseConfirmation = $0 }
        )) {
            Button("Cancel", role: .cancel) {
                appState.cancelCloseTab()
            }
            Button("Close", role: .confirm) {
                appState.confirmCloseTab()
            }
        } message: {
            Text("This tab has an active process. Are you sure you want to close it?")
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
