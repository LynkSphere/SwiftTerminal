import SwiftUI

struct SessionBrowserView: View {
    let workspace: Workspace
    var onSelect: (() -> Void)?

    @Environment(AppState.self) private var appState
    @AppStorage("defaultChatMode") private var defaultChatMode: AgentProvider = .claude

    private var regularChats: [Chat] {
        workspace.chats.filter { !$0.isArchived }
    }

    private var archivedChats: [Chat] {
        workspace.chats.filter { $0.isArchived }
    }

    var body: some View {
        List {
            if !regularChats.isEmpty {
                // Section("Sessions") {
                    ForEach(regularChats) { chat in
                        storedSessionRow(chat)
                    }
                // }
            }

            if !archivedChats.isEmpty {
                Section("Archived") {
                    ForEach(archivedChats) { chat in
                        storedSessionRow(chat)
                    }
                }
            }
        }
        .overlay {
            if workspace.chats.isEmpty {
                ContentUnavailableView {
                    Label("No Sessions", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Start a new chat to begin.")
                } actions: {
                    newChatButton
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                newChatButton
            }
        }
    }

    private var newChatButton: some View {
        Menu {
            ForEach(AgentProvider.allCases, id: \.self) { provider in
                Button {
                    let chat = workspace.addSession(provider: provider)
                    appState.selectedSession = chat
                    onSelect?()
                } label: {
                    Label(provider.rawValue, image: provider.imageName)
                }
            }
        } label: {
            Label("New Chat", systemImage: "plus")
        } primaryAction: {
            let chat = workspace.addSession(provider: defaultChatMode)
            appState.selectedSession = chat
            onSelect?()
        }
    }

    private func storedSessionRow(_ chat: Chat) -> some View {
        Button {
            appState.selectedSession = chat
            onSelect?()
        } label: {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(chat.title)
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            if chat.turnCount > 0 {
                                Text("\(chat.turnCount) turns")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            Text(chat.date, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.quaternary)
                        }
                    }
                } icon: {
                    Image(chat.provider.imageName)
                        .foregroundStyle(
                            chat.isActive ? chat.provider.color : .secondary
                        )
                }

                Spacer()

                if chat.isActive {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if chat.isActive {
                Button {
                    chat.disconnect()
                } label: {
                    Label("Disconnect", systemImage: "bolt.slash")
                }
            }

            Button {
                chat.isArchived.toggle()
            } label: {
                if chat.isArchived {
                    Label("Unarchive", systemImage: "tray.and.arrow.up")
                } else {
                    Label("Archive", systemImage: "archivebox")
                }
            }

            Button(role: .destructive) {
                if appState.selectedSession?.id == chat.id {
                    appState.selectedSession = nil
                }
                workspace.removeSession(chat)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
