import Foundation

@MainActor
final class ClaudeAgentAdapter: AgentProviderAdapter {
    let provider = AgentProvider.claude
    let capabilities: AgentCapabilities = [.deleteThread, .renameThread]
    var onEvent: ((AgentEvent) -> Void)?
    private let history = ClaudeSessionHistory()
    private let defaults: UserDefaults
    private var backgroundIDs: [String: String]
    private var backgroundSessions: [String: ClaudeBackgroundSession] = [:]
    private var watchers: [FileSystemWatcher] = []
    private var statusTask: Task<Void, Never>?
    private var statusRefreshRequested = false
    private var statusRevision = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        backgroundIDs = defaults.dictionary(forKey: "integration.claude.backgroundIDs") as? [String: String] ?? [:]
    }

    func listThreads() async throws -> [AgentThread] {
        try startWatching()
        try await refreshBackgroundSessions()
        let history = try await history.listThreads().map(withStatus)
        let listedIDs = Set(history.map(\.sessionID))
        let drafts = backgroundSessions.values.compactMap(\.thread).filter { !listedIDs.contains($0.sessionID) }
        return AgentThread.unique(history + drafts)
    }

    func readThread(_ id: String) async throws -> AgentThread? {
        try await history.readThread(id).map(withStatus) ?? backgroundSessions[id]?.thread
    }

    func renameThread(_ thread: AgentThread, to title: String) async throws {
        try await history.renameThread(thread.sessionID, to: title, directory: thread.directory)
    }

    func deleteThread(_ thread: AgentThread) async throws {
        try await stopThread(thread)
        try await history.deleteThread(thread.sessionID, directory: thread.directory)
        backgroundIDs[thread.sessionID] = nil
        backgroundSessions[thread.sessionID] = nil
        saveBackgroundIDs()
        onEvent?(.threadDeleted(sessionID: thread.sessionID))
    }

    func createThread(directory: String) async throws -> AgentThread {
        let session = try await startBackgroundSession(directory: directory)
        guard var thread = session.thread else {
            throw IntegrationError(message: "Claude did not provide a session identifier.")
        }
        thread.title = "New Claude thread"
        return thread
    }

    func prepareLaunch(for thread: AgentThread, intent: AgentLaunchIntent) async throws -> AgentLaunch {
        guard UUID(uuidString: thread.sessionID) != nil else {
            throw IntegrationError(message: "Invalid Claude session identifier.")
        }
        try startWatching()
        let sessions = try await listBackgroundSessions()
        let session: ClaudeBackgroundSession
        if let existing = sessions.first(where: { $0.kind == "background" && $0.sessionID == thread.sessionID }) {
            session = existing
        } else {
            session = try await startBackgroundSession(directory: thread.directory, resuming: thread.sessionID)
        }
        guard let id = session.id else { throw IntegrationError(message: "Claude did not provide a background session identifier.") }
        backgroundIDs[thread.sessionID] = id
        if backgroundSessions[thread.sessionID]?.id != id { backgroundSessions[thread.sessionID] = session }
        saveBackgroundIDs()
        return AgentLaunch(executable: "claude", arguments: ["attach", id])
    }

    func stopThread(_ thread: AgentThread) async throws {
        let sessions = try await listBackgroundSessions()
        guard let session = sessions.first(where: { $0.kind == "background" && $0.sessionID == thread.sessionID }),
              let id = session.id else { return }
        _ = try await IntegrationProcess.run("claude", arguments: ["stop", id], directory: thread.directory)
        try await refreshBackgroundSessions()
    }

    func didExit(_ thread: AgentThread) {
        requestStatusRefresh()
    }

    func setEnabled(_ isEnabled: Bool) {
        if !isEnabled {
            watchers.forEach { $0.stop() }
            watchers.removeAll()
            statusTask?.cancel()
        }
    }

    private func startBackgroundSession(directory: String, resuming sessionID: String? = nil) async throws -> ClaudeBackgroundSession {
        let settings = #"{"env":{"CLAUDE_CODE_DISABLE_BG_EXIT_HANDOFF":"1"}}"#
        var arguments = ["--bg", "--settings", settings]
        if let sessionID { arguments += ["--resume", sessionID] }
        let output = try await IntegrationProcess.run("claude", arguments: arguments, directory: directory, timeout: .seconds(120))
        guard let line = String(decoding: output, as: UTF8.self).split(separator: "\n").first(where: { $0.hasPrefix("backgrounded") }),
              let field = line.split(separator: "·").dropFirst().first,
              let identifier = field.split(whereSeparator: \.isWhitespace).first else {
            throw IntegrationError(message: "Claude did not return a background session identifier.")
        }
        let id = String(identifier)
        do {
            let clock = ContinuousClock()
            let deadline = clock.now + .seconds(30)
            while clock.now < deadline {
                try Task.checkCancellation()
                if let session = try await listBackgroundSessions().first(where: { $0.kind == "background" && $0.id == id }),
                   let thread = session.thread {
                    guard sessionID == nil || thread.sessionID == sessionID else {
                        throw IntegrationError(message: "This Claude conversation is already open elsewhere. Close that session before opening it here.")
                    }
                    backgroundIDs[thread.sessionID] = id
                    backgroundSessions[thread.sessionID] = session
                    saveBackgroundIDs()
                    try startWatching()
                    return session
                }
                try await Task.sleep(for: .milliseconds(200))
            }
            throw IntegrationError(message: "Claude did not provide its background conversation identifier.")
        } catch {
            _ = try? await Task {
                try await IntegrationProcess.run("claude", arguments: ["stop", id], directory: directory)
            }.value
            throw error
        }
    }

    private func listBackgroundSessions() async throws -> [ClaudeBackgroundSession] {
        let data = try await IntegrationProcess.run("claude", arguments: ["agents", "--json", "--all"])
        return try JSONDecoder().decode([ClaudeBackgroundSession].self, from: data)
    }

    private func refreshBackgroundSessions() async throws {
        statusRevision += 1
        let revision = statusRevision
        let expectedIDs = backgroundIDs
        let sessions = try await listBackgroundSessions()
        try Task.checkCancellation()
        guard revision == statusRevision else { return }
        let presentIDs = Set(sessions.filter { $0.kind == "background" }.compactMap(\.sessionID))
        for (sessionID, id) in expectedIDs where backgroundIDs[sessionID] == id && !presentIDs.contains(sessionID) {
            backgroundSessions[sessionID] = nil
            backgroundIDs[sessionID] = nil
            onEvent?(.threadUpdated(sessionID: sessionID, update: AgentThreadUpdate(status: .unknown)))
        }
        saveBackgroundIDs()
        for session in sessions where session.kind == "background" {
            guard let sessionID = session.sessionID, let id = session.id, backgroundIDs[sessionID] == id else { continue }
            let previous = backgroundSessions.updateValue(session, forKey: sessionID)
            guard previous != session else { continue }
            onEvent?(.threadUpdated(sessionID: sessionID, update: AgentThreadUpdate(status: session.threadStatus)))
            onEvent?(.threadInvalidated(sessionID: sessionID))
        }
    }

    private func startWatching() throws {
        guard watchers.isEmpty else { return }
        let config = IntegrationProcess.environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude")
        let directories = ["jobs", "sessions"].map { config.appending(path: $0) }
        for directory in directories {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        watchers = directories.map { directory in
            FileSystemWatcher(url: directory, latency: 0.3, ignoredSubstrings: []) { [weak self] in
                Task { @MainActor [weak self] in self?.requestStatusRefresh() }
            }
        }
    }

    private func requestStatusRefresh() {
        guard !watchers.isEmpty else { return }
        statusRefreshRequested = true
        guard statusTask == nil else { return }
        statusTask = Task { [weak self] in
            guard let self else { return }
            defer { self.statusTask = nil }
            do {
                repeat {
                    self.statusRefreshRequested = false
                    try await Task.sleep(for: .milliseconds(300))
                    try await self.refreshBackgroundSessions()
                } while self.statusRefreshRequested
            } catch is CancellationError {
            } catch {
                self.onEvent?(.listInvalidated)
            }
        }
    }

    private func saveBackgroundIDs() {
        defaults.set(backgroundIDs, forKey: "integration.claude.backgroundIDs")
    }

    private func withStatus(_ source: AgentThread) -> AgentThread {
        var thread = source
        thread.status = backgroundSessions[thread.sessionID]?.threadStatus ?? .unknown
        return thread
    }

}
