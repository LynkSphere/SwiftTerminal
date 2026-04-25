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
                if chat.isArchived {
                    Label("Unarchive", systemImage: "tray.and.arrow.up")
                } else {
                    Label("Archive", systemImage: "archivebox")
                }
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
    }
}
