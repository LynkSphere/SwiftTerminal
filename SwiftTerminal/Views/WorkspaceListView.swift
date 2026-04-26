import SwiftUI
import AppKit

struct WorkspaceListView: View {
    @Environment(AppState.self) private var appState
    @Environment(WorkspaceStore.self) private var store
    @AppStorage("hideSettingsButton") private var hideSettingsButton = false
    @AppStorage("sidebarRowSize") private var sidebarRowSize: SidebarRowSizePreference = .medium
    @AppStorage("defaultChatMode") private var defaultChatMode: AgentProvider = .claude
    @AppStorage("defaultPermissionMode") private var defaultPermissionMode: PermissionMode = .bypassPermissions

    @State private var browsingWorkspace: Workspace?

    let searchText: String

    init(searchText: String = "") {
        self.searchText = searchText
    }

    private var visibleWorkspaces: [Workspace] {
        let base = store.workspaces.filter { appState.showArchivedWorkspaces || !$0.isArchived }
        guard !searchText.isEmpty else { return base }
        return base.filter { $0.name.localizedStandardContains(searchText) }
    }

    var body: some View {
        @Bindable var appState = appState
        List(selection: $appState.selectedChat) {
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
                            .padding(.leading, -10)
                            .tag(chat)
                    }
                    .onMove { source, destination in
                        withAnimation {
                            var newOrder = chats
                            newOrder.move(fromOffsets: source, toOffset: destination)
                            workspace.reorderChats(newOrder)
                        }
                    }
                } label: {
                    WorkspaceRow(workspace: workspace) {
                        browsingWorkspace = workspace
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation {
                            if appState.expandedWorkspaceIDs.contains(workspaceID) {
                                appState.expandedWorkspaceIDs.remove(workspaceID)
                            } else {
                                appState.expandedWorkspaceIDs.insert(workspaceID)
                                if !workspace.chats.contains(where: { !$0.isArchived }) {
                                    let chat = workspace.addChat(provider: defaultChatMode, permissionMode: defaultPermissionMode)
                                    appState.selectedChat = chat
                                }
                            }
                        }
                    }
                    .selectionDisabled()
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
        .environment(\.sidebarRowSize, sidebarRowSize.sidebarRowSize)
        .sheet(item: $browsingWorkspace) { workspace in
            NavigationStack {
                ChatBrowserView(workspace: workspace, onSelect: {
                    browsingWorkspace = nil
                })
                .navigationTitle(workspace.name)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { browsingWorkspace = nil }
                    }
                }
            }
            .frame(minWidth: 480, minHeight: 520)
        }
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
        browsingWorkspace = workspace
    }
}
