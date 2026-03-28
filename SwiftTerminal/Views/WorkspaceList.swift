import SwiftUI
import AppKit

struct SidebarItem: Identifiable, Hashable {
    let id: SidebarSelection
    let label: String
    let icon: String
    var children: [SidebarItem]?
}

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

    private var sidebarItems: [SidebarItem] {
        filteredWorkspaces.map { workspace in
            let sessionChildren = workspace.sessions.map { service in
                let label = if let sid = service.session.sessionID {
                    String(sid.prefix(8))
                } else {
                    "New Session"
                }
                return SidebarItem(
                    id: .session(workspaceID: workspace.id, serviceID: service.id),
                    label: label,
                    icon: "bubble.left"
                )
            }
            return SidebarItem(
                id: .workspace(workspace.id),
                label: workspace.name,
                icon: "folder",
                children: sessionChildren.isEmpty ? nil : sessionChildren
            )
        }
    }

    var body: some View {
        @Bindable var appState = appState

        List(sidebarItems, children: \.children, selection: $appState.sidebarSelection) { item in
            sidebarRow(for: item)
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

    @ViewBuilder
    private func sidebarRow(for item: SidebarItem) -> some View {
        switch item.id {
        case .workspace(let id):
            if let workspace = appState.workspaces.first(where: { $0.id == id }) {
                WorkspaceRow(
                    workspace: workspace,
                    renamingWorkspace: $renamingWorkspace
                )
            }
        case .session(let workspaceID, let serviceID):
            if let workspace = appState.workspaces.first(where: { $0.id == workspaceID }),
               let service = workspace.sessions.first(where: { $0.id == serviceID }) {
                Label(
                    service.session.sessionID.map { String($0.prefix(8)) } ?? "New Session",
                    systemImage: "bubble.left"
                )
                .font(.subheadline)
                .contextMenu {
                    Button(role: .destructive) {
                        workspace.removeSession(service)
                        if appState.sidebarSelection == .session(workspaceID: workspaceID, serviceID: serviceID) {
                            appState.sidebarSelection = .workspace(workspaceID)
                        }
                    } label: {
                        Label("Delete Session", systemImage: "trash")
                    }
                }
            }
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
