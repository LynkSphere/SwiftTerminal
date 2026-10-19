import Foundation

@MainActor
final class ClaudeAgentAdapter: AgentProviderAdapter {
    let provider = AgentProvider.claude
    let capabilities: AgentCapabilities = [.deleteThread]
    let activityPolicy = AgentActivityPolicy.observedTransitions
    var onEvent: ((AgentEvent) -> Void)?
    // Retained CLI terminals keep using this address even while the integration is hidden.
    private let hooks = ClaudeHookServer()
    /// Only terminals launched by this adapter can report authenticated live hook events.
    private var statuses: [String: AgentThreadStatus] = [:]

    init() {
        hooks.onEvent = { [weak self] event in self?.receive(event) }
    }

    func listThreads() async throws -> [AgentThread] {
        try Self.parseHistory(await runHistory()).map(withStatus)
    }

    func readThread(_ id: String) async throws -> AgentThread? {
        try Self.parseHistory(await runHistory(arguments: [id])).first.map(withStatus)
    }

    func deleteThread(_ thread: AgentThread) async throws {
        _ = try await runHistory(arguments: ["--delete", thread.sessionID, thread.directory])
        statuses[thread.sessionID] = nil
        onEvent?(.threadDeleted(sessionID: thread.sessionID))
    }

    private func runHistory(arguments: [String] = []) async throws -> Data {
        guard let helper = Bundle.main.url(forResource: "claude-history", withExtension: "mjs", subdirectory: "Integrations") else {
            throw IntegrationError(message: "The Claude session helper is missing. Rebuild SwiftTerminal.")
        }
        let sdk = try await ClaudeSDK.url()
        return try await IntegrationProcess.run("node", arguments: [helper.path, sdk.path] + arguments)
    }

    func createThread(directory: String) async throws -> AgentThread {
        AgentThread(sessionID: UUID().uuidString.lowercased(), provider: provider,
                    title: "New Claude thread", directory: directory, updatedAt: .now, status: .idle)
    }

    func prepareLaunch(for thread: AgentThread, intent: AgentLaunchIntent) async throws -> AgentLaunch {
        guard UUID(uuidString: thread.sessionID) != nil else {
            throw IntegrationError(message: "Invalid Claude session identifier.")
        }
        let settings = try await hooks.settings()
        statuses[thread.sessionID] = .idle
        return AgentLaunch(executable: "claude", arguments: [
            intent == .create ? "--session-id" : "--resume", thread.sessionID, "--settings", settings
        ])
    }

    func title(from reportedTitle: String) -> String? {
        AgentTerminalTitle.displayTitle(reportedTitle: reportedTitle, foregroundCommand: "claude")
    }

    func didExit(_ thread: AgentThread) {
        statuses[thread.sessionID] = thread.status
    }

    func forgetThread(_ sessionID: String) {
        statuses[sessionID] = nil
    }

    private func withStatus(_ source: AgentThread) -> AgentThread {
        var thread = source
        thread.status = statuses[thread.sessionID] ?? .unknown
        return thread
    }

    private func receive(_ event: ClaudeHookEvent) {
        guard statuses[event.sessionID] != nil, let status = event.status else { return }
        statuses[event.sessionID] = status
        let title = event.sessionTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        onEvent?(.threadUpdated(sessionID: event.sessionID, update: AgentThreadUpdate(
            status: status, title: title.flatMap { $0.isEmpty ? nil : $0 },
            updatedAt: event.name == "UserPromptSubmit" ? .now : nil
        )))
        if ["SessionStart", "UserPromptSubmit", "Stop", "StopFailure", "SessionEnd"].contains(event.name) {
            onEvent?(.threadInvalidated(sessionID: event.sessionID))
        }
    }

    private static func parseHistory(_ history: Data) throws -> [AgentThread] {
        guard let rows = try JSONSerialization.jsonObject(with: history) as? [[String: Any]] else {
            throw IntegrationError(message: "Claude returned invalid session history.")
        }
        let threads: [AgentThread] = rows.compactMap { row in
            guard let id = row["sessionId"] as? String, let directory = row["cwd"] as? String else { return nil }
            return AgentThread(
                sessionID: id, provider: .claude, title: row["title"] as? String ?? "Claude thread", directory: directory,
                updatedAt: Date(timeIntervalSince1970: (row["lastModified"] as? Double ?? 0) / 1000), status: .unknown,
                hasProviderTitle: row["hasProviderTitle"] as? Bool ?? false
            )
        }
        return AgentThread.unique(threads)
    }
}
