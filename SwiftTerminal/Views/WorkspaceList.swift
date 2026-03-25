import SwiftUI
import AppKit

struct WorkspaceList: View {
    @Environment(AppState.self) private var appState
    @State private var renamingWorkspace: Workspace?
    @State private var searchText = ""

    private var filteredWorkspaces: [Workspace] {
        guard !searchText.isEmpty else { return appState.workspaces }
        return appState.workspaces.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        @Bindable var appState = appState

        List(selection: $appState.selectedWorkspace) {
            ForEach(filteredWorkspaces) { workspace in
                WorkspaceRow(
                    workspace: workspace,
                    renamingWorkspace: $renamingWorkspace
                )
                .tag(workspace)
            }
            .onMove { source, destination in
                appState.moveWorkspaces(from: source, to: destination)
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Filter workspaces")
        .safeAreaInset(edge: .bottom) {
            Button {
                chooseDirectoryForNewWorkspace()
            } label: {
                Label("New Workspace", systemImage: "plus")
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private func chooseDirectoryForNewWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a directory for the new workspace"
        panel.prompt = "Select"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        appState.addWorkspace(directory: url.path)
    }
}

