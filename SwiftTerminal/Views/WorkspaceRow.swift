import SwiftUI

struct WorkspaceRow: View {
    @Environment(AppState.self) private var appState
    @Environment(WorkspaceStore.self) private var store
    @AppStorage("defaultChatMode") private var defaultChatMode: AgentProvider = .claude
    @AppStorage("defaultPermissionMode") private var defaultPermissionMode: PermissionMode = .bypassPermissions

    let workspace: Workspace

    @State private var isRenaming = false
    @FocusState private var isNameFieldFocused: Bool

    private var isExpanded: Bool {
        appState.expandedWorkspaceIDs.contains("w:\(workspace.id.uuidString)")
    }

    private var notificationCount: Int {
        let selectedID = appState.selectedChat?.id
        return workspace.chats.lazy
            .filter { !$0.isArchived && $0.hasNotification && $0.id != selectedID }
            .count
    }

    private var badgeCount: Int {
        if isExpanded { return workspace.connectedChatCount }
        return notificationCount > 0 ? notificationCount : workspace.connectedChatCount
    }

    private var badgeIsProminent: Bool {
        !isExpanded && notificationCount > 0
    }

    var body: some View {
        HStack(spacing: 8) {
            if workspace.projectType != .unknown {
                Image(workspace.projectType.iconName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "folder")
            }

            if isRenaming {
                TextField("Workspace Name", text: Bindable(workspace).name)
                    .textFieldStyle(.plain)
                    .focused($isNameFieldFocused)
                    .onSubmit { isRenaming = false }
                    .onExitCommand { isRenaming = false }
                    .onAppear { isNameFieldFocused = true }
            } else {
                Text(workspace.name)
                    .lineLimit(1)
            }
        }
        .badge(badgeCount)
        .badgeProminence(badgeIsProminent ? .increased : .standard)
        .contextMenu {
            Menu {
                ForEach(AgentProvider.allCases, id: \.self) { provider in
                    Button {
                        let chat = workspace.addChat(provider: provider, permissionMode: defaultPermissionMode)
                        appState.expandedWorkspaceIDs.insert("w:\(workspace.id.uuidString)")
                        appState.selectedWorkspace = workspace
                        appState.selectedChat = chat
                    } label: {
                        Label(provider.rawValue, image: provider.imageName)
                    }
                }
            } label: {
                Label("New Chat", systemImage: "plus")
            } primaryAction: {
                let chat = workspace.addChat(provider: defaultChatMode, permissionMode: defaultPermissionMode)
                appState.expandedWorkspaceIDs.insert("w:\(workspace.id.uuidString)")
                appState.selectedWorkspace = workspace
                appState.selectedChat = chat
            }
            
            Divider()
            
            RenameButton()
            
            Menu {
                ForEach(ProjectType.allCases, id: \.self) { type in
                    Button {
                        workspace.projectType = type
                    } label: {
                        Label {
                            Text(type.displayName)
                        } icon: {
                            if workspace.projectType == type {
                                Image(systemName: "checkmark")
                            } else if !type.iconName.isEmpty {
                                Image(type.iconName)
                            }
                        }
                    }
                }
                
                Divider()
                
                Button("Auto-Detect") {
                    workspace.detectProjectType()
                }
            } label: {
                Label("Project Type", systemImage: "shippingbox")
            }

            Divider()
            Button {
                workspace.disconnectAllActiveChats()
            } label: {
                Label("Disconnect All Chats", systemImage: "bolt.slash")
            }
            .disabled(!workspace.hasActiveChats)

            Button {
                workspace.killAllRunningTerminals()
            } label: {
                Label("Kill All Terminals", systemImage: "xmark.octagon")
            }
            .disabled(!workspace.hasRunningTerminals)

            Divider()
            Button(role: .destructive) {
                if appState.selectedWorkspace === workspace {
                    appState.selectedWorkspace = nil
                    appState.selectedChat = nil
                }
                store.deleteWorkspace(workspace)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .renameAction {
            isRenaming = true
        }
    }
}
