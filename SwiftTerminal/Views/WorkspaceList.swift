import SwiftUI

struct WorkspaceList: View {
    @Environment(AppState.self) private var appState
    @State private var renamingWorkspace: Workspace?

    var body: some View {
        @Bindable var appState = appState

        List(selection: $appState.selectedWorkspace) {
            ForEach(appState.workspaces) { workspace in
                WorkspaceRow(
                    workspace: workspace,
                    renamingWorkspace: $renamingWorkspace
                )
                .tag(workspace)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                appState.addWorkspace()
            } label: {
                Label("New Workspace", systemImage: "plus")
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }
}

