import SwiftUI
import SwiftData
import AppKit

struct WorkspaceListView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Workspace.sortOrder) private var workspaces: [Workspace]
    @State private var searchText = ""

    private var filteredWorkspaces: [Workspace] {
        guard !searchText.isEmpty else { return workspaces }
        return workspaces.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List(selection: Bindable(appState).selectedSession) {
            ForEach(filteredWorkspaces) { workspace in
                DisclosureGroup {
                    ForEach(workspace.sessions) { session in
                        Label(
                            session.sdkSessionID.map { String($0.prefix(8)) } ?? "New Session",
                            systemImage: "bubble.left"
                        )
                        .tag(session)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                if appState.selectedSession == session {
                                    appState.selectedSession = nil
                                }
                                workspace.removeSession(session)
                            } label: {
                                Label("Delete Session", systemImage: "trash")
                                    .labelStyle(.iconOnly)
                            }
                        }
                    }
                } label: {
                    WorkspaceRow(workspace: workspace)
                }
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
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
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
        let name = URL(fileURLWithPath: url.path).lastPathComponent
        let workspace = Workspace(name: name, directory: url.path, sortOrder: workspaces.count)
        modelContext.insert(workspace)
    }
}
