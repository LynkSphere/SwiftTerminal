import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

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
        .alert("Close Tab?", isPresented: $appState.showCloseConfirmation) {
            Button("Cancel", role: .cancel) {
                appState.tabToClose = nil
            }
            Button("Close", role: .confirm) {
                if let tab = appState.tabToClose {
                    appState.selectedWorkspace?.closeTab(tab)
                }
                appState.tabToClose = nil
            }
        } message: {
            Text("This tab has an active process. Are you sure you want to close it?")
        }
    }
}
