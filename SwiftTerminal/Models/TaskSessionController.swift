import Foundation
import Observation

/// Coordinates local task processes and selection independently of provider history.
@MainActor
@Observable
final class TaskSessionController {
    private(set) var isOpening = false

    private let integrations: AgentIntegrationStore
    private let appState: AppState
    private let workspaces: WorkspaceStore

    init(integrations: AgentIntegrationStore, appState: AppState, workspaces: WorkspaceStore) {
        self.integrations = integrations
        self.appState = appState
        self.workspaces = workspaces
    }

    func compose(provider: AgentProvider, workspace: Workspace) async -> Bool {
        guard !isOpening, integrations.enabledProviders.contains(provider) else { return false }
        isOpening = true
        defer { isOpening = false }
        do {
            try validateDirectory(workspace.directory)
            let thread = try await integrations.createThread(provider: provider, directory: workspace.directory)
            try Task.checkCancellation()
            guard canOpen(thread) else { return false }
            let command = try await integrations.prepareCommand(for: thread, isNew: provider == .claude)
            try Task.checkCancellation()
            guard canOpen(thread) else { return false }
            integrations.registerDraft(thread)
            launch(thread, command: command, workspace: workspace)
            return true
        } catch is CancellationError {
            return false
        } catch {
            integrations.actionError = error.localizedDescription
            return false
        }
    }

    func open(_ thread: AgentThread) async {
        guard !isOpening, canOpen(thread) else { return }
        isOpening = true
        defer { isOpening = false }
        if let session = appState.sessions[thread.id], !session.terminal.hasExited {
            session.thread = thread
            appState.show(session)
            integrations.setViewedThread(thread.id)
            return
        }
        do {
            try validateDirectory(thread.directory)
            let command = try await integrations.prepareCommand(for: thread)
            try Task.checkCancellation()
            guard canOpen(thread) else { return }
            let workspace = workspace(for: thread.directory)
            if let session = appState.sessions[thread.id] {
                session.thread = thread
                session.restart(command: command)
                observeTerminal(of: session)
                appState.show(session)
            } else {
                launch(thread, command: command, workspace: workspace)
            }
        } catch is CancellationError {
        } catch {
            integrations.actionError = error.localizedDescription
        }
    }

    func settle(_ thread: AgentThread) {
        integrations.settle(thread)
        appState.closeSession(thread.id)
    }

    private func canOpen(_ thread: AgentThread) -> Bool {
        integrations.enabledProviders.contains(thread.provider) && !integrations.settledThreadIDs.contains(thread.id)
    }

    private func launch(_ thread: AgentThread, command: String, workspace: Workspace) {
        let session = TaskSession(thread: thread, workspace: workspace, command: command)
        observeTerminal(of: session)
        appState.show(session)
    }

    private func observeTerminal(of session: TaskSession) {
        let terminal = session.terminal
        terminal.onTitleChange = { [weak self, weak session, weak terminal] title in
            guard let self, let session, session.terminal === terminal, !session.terminal.hasExited,
                  self.appState.sessions[session.id] === session else { return }
            self.integrations.recordTerminalTitle(title, threadID: session.id)
        }
        terminal.onProcessExit = { [weak self, weak session, weak terminal] code in
            guard let self, let session, session.terminal === terminal,
                  self.appState.sessions[session.id] === session else { return }
            self.integrations.recordProcessExit(threadID: session.id, code: code)
        }
    }

    private func workspace(for directory: String) -> Workspace {
        let url = URL(fileURLWithPath: directory).standardizedFileURL
        if let existing = workspaces.workspaces.first(where: { $0.url.standardizedFileURL == url }) {
            return existing
        }
        let workspace = Workspace(name: url.lastPathComponent, directory: directory)
        workspace.detectProjectType()
        workspaces.addWorkspace(workspace)
        return workspace
    }

    private func validateDirectory(_ directory: String) throws {
        var isDirectory: ObjCBool = false
        guard directory.hasPrefix("/"), FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw IntegrationError(message: "The project folder is no longer available: \(directory)")
        }
    }
}
