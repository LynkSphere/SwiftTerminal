import SwiftUI
import AppKit

struct WorkspaceListView: View {
    @Environment(AppState.self) private var appState
    @Environment(WorkspaceStore.self) private var store
    @AppStorage("hideSettingsButton") private var hideSettingsButton = false

    let searchText: String

    init(searchText: String = "") {
        self.searchText = searchText
    }

    private var visibleWorkspaces: [Workspace] {
        let base = store.workspaces.filter { appState.showArchivedWorkspaces || !$0.isArchived }
        guard !searchText.isEmpty else { return base }
        return base.filter { $0.name.localizedStandardContains(searchText) }
    }

    private var sidebarSelection: Binding<String?> {
        Binding(
            get: {
                if let chat = appState.selectedChat,
                   let workspace = appState.selectedWorkspace,
                   workspace.chats.contains(where: { $0.id == chat.id }) {
                    return "c:\(chat.id.uuidString)"
                } else if let workspace = appState.selectedWorkspace {
                    return "w:\(workspace.id.uuidString)"
                }
                return nil
            },
            set: { newValue in
                guard let id = newValue else {
                    appState.selectedWorkspace = nil
                    appState.selectedChat = nil
                    return
                }
                if id.hasPrefix("w:") {
                    let uuidStr = String(id.dropFirst(2))
                    appState.selectedWorkspace = store.workspaces.first { $0.id.uuidString == uuidStr }
                    appState.selectedChat = nil
                    if !appState.expandedWorkspaceIDs.contains(id) {
                        appState.expandedWorkspaceIDs.insert(id)
                    }
                } else if id.hasPrefix("c:") {
                    let uuidStr = String(id.dropFirst(2))
                    for workspace in store.workspaces {
                        if let chat = workspace.chats.first(where: { $0.id.uuidString == uuidStr }) {
                            appState.selectedWorkspace = workspace
                            appState.selectedChat = chat
                            return
                        }
                    }
                }
            }
        )
    }

    var body: some View {
        List(selection: sidebarSelection) {
            ForEach(visibleWorkspaces) { workspace in
                let workspaceID = "w:\(workspace.id.uuidString)"
                DisclosureGroup(isExpanded: Binding(
                    get: { appState.expandedWorkspaceIDs.contains(workspaceID) },
                    set: { isExpanded in
                        if isExpanded {
                            appState.expandedWorkspaceIDs.insert(workspaceID)
                        } else {
                            appState.expandedWorkspaceIDs.remove(workspaceID)
                        }
                    }
                )) {
                    let chats = workspace.chats
                        .filter { !$0.isArchived }
                        .sorted { $0.sortOrder < $1.sortOrder }
                    ForEach(chats) { chat in
                        ChatSidebarRow(chat: chat)
                            .tag("c:\(chat.id.uuidString)")
                    }
                    .onMove { source, destination in
                        withAnimation {
                            var newOrder = chats
                            newOrder.move(fromOffsets: source, toOffset: destination)
                            workspace.reorderChats(newOrder)
                        }
                    }
                } label: {
                    WorkspaceRow(workspace: workspace)
                        .tag(workspaceID)
                }
            }
            .onMove { source, destination in
                withAnimation {
                    let visible = visibleWorkspaces
                    let visibleIDs = Set(visible.map { $0.id })
                    let slots = store.workspaces.indices.filter { visibleIDs.contains(store.workspaces[$0].id) }

                    var newVisible = visible
                    newVisible.move(fromOffsets: source, toOffset: destination)

                    var newAll = store.workspaces
                    for (slot, ws) in zip(slots, newVisible) {
                        newAll[slot] = ws
                    }
                    store.reorderWorkspaces(newAll)
                }
            }
        }
        .environment(\.sidebarRowSize, .medium)
        .safeAreaBar(edge: .bottom) {
            HStack(spacing: 0) {
                Button {
                    chooseDirectoryForNewWorkspace()
                } label: {
                    Label("New Workspace", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if !hideSettingsButton {
                    SettingsLink {
                        Image(systemName: "gearshape")
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                }
            }
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
        let workspace = Workspace(name: name, directory: url.path)
        workspace.detectProjectType()
        store.addWorkspace(workspace)
        appState.selectedWorkspace = workspace
    }
}
