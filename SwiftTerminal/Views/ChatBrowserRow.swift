import SwiftUI

struct ChatBrowserRow: View {
    let chat: Chat
    let workspace: Workspace
    var onSelect: () -> Void

    @Environment(AppState.self) private var appState

    var body: some View {
        Button {
            appState.selectedChat = chat
            onSelect()
        } label: {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(chat.displayTitle)
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            if chat.turnCount > 0 {
                                Text("\(chat.turnCount) turns")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Text(ChatBrowserView.shortRelative(from: chat.date))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                } icon: {
                    Image(chat.provider.imageName)
                        .foregroundStyle(
                            chat.isActive ? chat.provider.color : .secondary
                        )
                }

                Spacer()

                if chat.session.isProcessing {
                    ProgressView()
                        .controlSize(.small)
                } else if chat.isActive {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                }
            }
            .contentShape(Rectangle())
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
                if !chat.isArchived {
                    chat.disconnect()
                }
                chat.isArchived.toggle()
            } label: {
                Label(
                    chat.isArchived ? "Unarchive" : "Archive",
                    systemImage: chat.isArchived ? "tray.and.arrow.up" : "archivebox"
                )
            }

            Button(role: .destructive) {
                if appState.selectedChat?.id == chat.id {
                    appState.selectedChat = nil
                }
                workspace.removeChat(chat)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                if !chat.isArchived {
                    if appState.selectedChat?.id == chat.id {
                        appState.selectedChat = nil
                    }
                    chat.disconnect()
                }
                chat.isArchived.toggle()
            } label: {
                Label(
                    chat.isArchived ? "Unarchive" : "Archive",
                    systemImage: chat.isArchived ? "tray.and.arrow.up" : "archivebox"
                )
            }
            .labelStyle(.iconOnly)
            .tint(.orange)

            Button {
                if chat.isActive {
                    chat.disconnect()
                } else {
                    chat.connectIfNeeded()
                }
            } label: {
                Label(
                    chat.isActive ? "Disconnect" : "Connect",
                    systemImage: chat.isActive ? "bolt.slash" : "bolt"
                )
            }
            .labelStyle(.iconOnly)
            .tint(chat.isActive ? .gray : .green)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                if appState.selectedChat?.id == chat.id {
                    appState.selectedChat = nil
                }
                workspace.removeChat(chat)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .labelStyle(.iconOnly)
        }
    }
}
