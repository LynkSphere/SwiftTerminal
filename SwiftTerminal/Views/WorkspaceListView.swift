import SwiftUI
import SwiftData
import AppKit

struct WorkspaceListView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Workspace.sortOrder) private var workspaces: [Workspace]
    @State private var searchText = ""
    @State private var expandedWorkspaces: Set<UUID> = []

    private var filteredWorkspaces: [Workspace] {
        guard !searchText.isEmpty else { return workspaces }
        return workspaces.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List(selection: Bindable(appState).selectedItem) {
            ForEach(filteredWorkspaces) { workspace in
                DisclosureGroup(isExpanded: Binding(
                    get: { expandedWorkspaces.contains(workspace.id) },
                    set: { isExpanded in
                        if isExpanded {
                            expandedWorkspaces.insert(workspace.id)
                        } else {
                            expandedWorkspaces.remove(workspace.id)
                        }
                    }
                )) {
                    ForEach(workspace.sessions) { session in
                        SessionRow(session: session, workspace: workspace)
                    }
                } label: {
                    WorkspaceRow(workspace: workspace)
                }
            }
        }
        .task {
            for workspace in workspaces where workspace.projectType == .unknown {
                workspace.detectProjectType()
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Filter workspaces")
        .onChange(of: appState.selectedItem) { _, newValue in
            guard case .workspace(let workspace) = newValue else { return }
            expandedWorkspaces.insert(workspace.id)
            appState.selectedItem = .session(workspace.emptyOrNewSession())
        }
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
        workspace.detectProjectType()
        modelContext.insert(workspace)
    }
}
