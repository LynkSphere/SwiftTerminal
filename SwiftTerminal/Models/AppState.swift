import SwiftUI

@MainActor
@Observable
final class AppState {
    private(set) var sessions: [String: TaskSession] = [:]
    private(set) var selectedSession: TaskSession?
    var showingCompose = false
    var sidebarVisibility: NavigationSplitViewVisibility = .automatic
    var showingInspector = true
    var pendingRunReplacement: Terminal?

    var selectedWorkspace: Workspace? { selectedSession?.workspace }
    var activeTerminal: Terminal? { selectedSession?.terminal }

    func show(_ session: TaskSession) {
        sessions[session.id] = session
        selectedSession = session
        session.terminal.hasBellNotification = false
    }

    func closeSession(_ id: String) {
        guard let session = sessions.removeValue(forKey: id) else { return }
        if selectedSession === session {
            selectedSession = nil
        }
        session.terminal.terminate()
    }

    func updateSessions(_ threads: [AgentThread], enabledProviders: [AgentProvider]) {
        for thread in threads {
            sessions[thread.id]?.thread = thread
            sessions[thread.id]?.terminal.title = thread.title
        }
        if let selectedSession, !enabledProviders.contains(selectedSession.thread.provider) {
            self.selectedSession = nil
        }
    }
}
