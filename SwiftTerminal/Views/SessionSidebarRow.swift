import SwiftUI

struct SessionSidebarRow: View {
    let session: Chat
    @Environment(AppState.self) private var appState

    @State private var isRenaming = false
    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        Label {
            if isRenaming {
                TextField("Chat Name", text: Bindable(session).title)
                    .textFieldStyle(.plain)
                    .focused($isNameFieldFocused)
                    .onSubmit { isRenaming = false }
                    .onExitCommand { isRenaming = false }
                    .onAppear { isNameFieldFocused = true }
            } else {
                Text(session.displayTitle)
                    .lineLimit(1)
            }
        } icon: {
            Image(session.provider.imageName)
                .foregroundStyle(session.isActive ? session.provider.color : .primary)
        }
        .contextMenu {
            Button {
                isRenaming = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            if session.isActive {
                Button {
                    session.disconnect()
                } label: {
                    Label("Disconnect", systemImage: "bolt.slash")
                }
            }

            Divider()
            
            Button {
                if appState.selectedSession?.id == session.id {
                    appState.selectedSession = nil
                }
                session.isArchived = true
            } label: {
                Label("Archive", systemImage: "archivebox")
            }

            Button(role: .destructive) {
                if appState.selectedSession?.id == session.id {
                    appState.selectedSession = nil
                }
                session.workspace?.removeSession(session)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .renameAction {
            isRenaming = true
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                if appState.selectedSession?.id == session.id {
                    appState.selectedSession = nil
                }
                session.isArchived = true
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .labelStyle(.iconOnly)
            .tint(.orange)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                if appState.selectedSession?.id == session.id {
                    appState.selectedSession = nil
                }
                session.workspace?.removeSession(session)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .labelStyle(.iconOnly)
        }
    }
}
