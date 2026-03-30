import SwiftUI

struct SessionRow: View {
    @Environment(AppState.self) private var appState

    let session: ChatSession
    let workspace: Workspace

    @State private var isRenaming = false
    @State private var renameText = ""
    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: session.service?.queryActive == true ? "bubble.left.fill" : "bubble.left")

            if isRenaming {
                TextField("Session Name", text: $renameText)
                    .textFieldStyle(.plain)
                    .focused($isNameFieldFocused)
                    .onSubmit { commitRename() }
                    .onExitCommand { isRenaming = false }
                    .onAppear {
                        renameText = session.name ?? ""
                        isNameFieldFocused = true
                    }
            } else {
                Text(session.name ?? "New Session")
                    .lineLimit(1)
                    .shimmerWithoutRedact(when: session.service?.isStreaming == true)
            }
        }
        .badge(session.hasNotification ? "" : nil)
        .badgeProminence(.increased)
        .tag(SidebarSelection.session(session))
        .contextMenu {
            Button("Fork Session", systemImage: "arrow.triangle.branch") {
                forkSession()
            }
            .disabled(session.externalSessionID == nil)

            Divider()

            RenameButton()
                .disabled(session.externalSessionID == nil)

            Divider()

            Button("Stop Session", systemImage: "xmark", role: .destructive) {
                session.resolveService().disconnectProcess()
            }
            .disabled(session.service?.queryActive != true)
            
            Button("Delete Session", systemImage: "trash", role: .destructive) {
                deleteSession()
            }
        }
        .renameAction {
            isRenaming = true
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                deleteSession()
            } label: {
                Label("Delete", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
        }
        .swipeActions(edge: .leading) {
            if session.service?.queryActive == true {
                Button {
                    session.resolveService().disconnectProcess()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .labelStyle(.iconOnly)
                }
                .tint(.orange)
            }
        }
    }

    private func commitRename() {
        isRenaming = false
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != session.name else { return }
        let service = session.resolveService()
        Task {
            await service.renameSession(to: trimmed)
        }
    }

    private func forkSession() {
        let service = session.resolveService()
        Task {
            guard let forked = await service.forkSession() else { return }
            await MainActor.run {
                appState.selectedItem = .session(forked)
            }
        }
    }

    private func deleteSession() {
        if appState.selectedSession == session {
            appState.selectedItem = nil
        }
        workspace.removeSession(session)
    }
}
