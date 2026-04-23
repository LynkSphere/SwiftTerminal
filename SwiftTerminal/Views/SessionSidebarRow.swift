import SwiftUI

struct SessionSidebarRow: View {
    let session: Chat
    @Environment(AppState.self) private var appState

    var body: some View {
        Label {
            Text(session.title)
                .lineLimit(1)
        } icon: {
            Image(session.provider.imageName)
                .foregroundStyle(session.isActive ? session.provider.color : .primary)
        }
        .contextMenu {
            if session.isActive {
                Button {
                    session.disconnect()
                } label: {
                    Label("Disconnect", systemImage: "bolt.slash")
                }
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
    }
}
