import Foundation
import Observation

@MainActor
@Observable
final class AgentIntegrationStore {
    var codexEnabled: Bool {
        didSet {
            defaults.set(codexEnabled, forKey: AgentProvider.codex.settingsKey)
            if !codexEnabled { codex.close() }
        }
    }
    var claudeEnabled: Bool { didSet { defaults.set(claudeEnabled, forKey: AgentProvider.claude.settingsKey) } }
    private(set) var threads: [AgentThread] = []
    private(set) var errors: [AgentProvider: String] = [:]
    private(set) var isRefreshing = false
    var actionError: String?
    var showSettledThreads = false
    private(set) var settledThreadIDs: Set<String>
    private var activity: [String: ThreadActivity]
    @ObservationIgnored private var viewedThreadID: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let codex = CodexIntegration()
    @ObservationIgnored private let claudeHooks = ClaudeHookServer()
    @ObservationIgnored private var claudeStatuses: [String: AgentThreadStatus] = [:]
    @ObservationIgnored private var revisions: [String: Int] = [:]
    @ObservationIgnored private var metadataRequests: Set<String> = []
    @ObservationIgnored private var metadataTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshRequested = false
    @ObservationIgnored private var drafts: [String: AgentThread] = [:]
    @ObservationIgnored private var terminalTitles: [String: String]

    var enabledProviders: [AgentProvider] {
        AgentProvider.allCases.filter { $0 == .codex ? codexEnabled : claudeEnabled }
    }
    var isEnabled: Bool { codexEnabled || claudeEnabled }
    var visibleThreads: [AgentThread] {
        threads.filter { enabledProviders.contains($0.provider) && (showSettledThreads || !settledThreadIDs.contains($0.id)) }
            .sorted(by: AgentThread.newestFirst)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        terminalTitles = defaults.dictionary(forKey: "integration.terminalTitles") as? [String: String] ?? [:]
        settledThreadIDs = Set(defaults.stringArray(forKey: "integration.settledThreadIDs") ?? [])
        activity = defaults.data(forKey: "integration.threadActivity")
            .flatMap { try? JSONDecoder().decode([String: ThreadActivity].self, from: $0) } ?? [:]
        codexEnabled = defaults.bool(forKey: AgentProvider.codex.settingsKey)
        claudeEnabled = defaults.bool(forKey: AgentProvider.claude.settingsKey)
        codex.onStatusChange = { [weak self] id, status in
            guard let self, self.codexEnabled, let index = self.threads.firstIndex(where: { $0.provider == .codex && $0.sessionID == id }) else { return }
            var thread = self.threads[index]
            thread.status = status
            self.threads[index] = self.reconcile(thread)
            self.revisions[thread.id, default: 0] += 1
            self.saveActivity()
        }
        codex.onReadStateChange = { [weak self] id, readState in
            guard let self, self.codexEnabled, let index = self.threads.firstIndex(where: { $0.provider == .codex && $0.sessionID == id }) else { return }
            var thread = self.threads[index]
            thread.readState = readState
            self.threads[index] = self.reconcile(thread)
            self.revisions[thread.id, default: 0] += 1
            self.saveActivity()
        }
        codex.onThreadChange = { [weak self] id in
            self?.requestMetadata("codex:\(id)")
        }
        codex.onListChange = { [weak self] in
            guard let self, self.codexEnabled else { return }
            Task { await self.refresh() }
        }
        codex.onDisconnect = { [weak self] in
            guard let self, self.codexEnabled else { return }
            Task { await self.refresh() }
        }
        claudeHooks.onEvent = { [weak self] event in self?.receiveClaudeEvent(event) }
    }

    private func receiveClaudeEvent(_ event: ClaudeHookEvent) {
        let id = "claude:\(event.sessionID)"
        guard claudeEnabled, claudeStatuses[id] != nil,
              let status = event.status, let index = threads.firstIndex(where: { $0.id == id }) else { return }
        claudeStatuses[id] = status
        var thread = threads[index]
        thread.status = status
        if let title = event.sessionTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            thread.title = title
            thread.hasProviderTitle = true
        }
        if event.name == "UserPromptSubmit" { thread.updatedAt = .now }
        threads[index] = reconcile(thread)
        revisions[id, default: 0] += 1
        saveActivity()
        if ["SessionStart", "UserPromptSubmit", "Stop", "StopFailure", "SessionEnd"].contains(event.name) {
            requestMetadata(id)
        }
    }

    private func requestMetadata(_ id: String) {
        guard threads.contains(where: { $0.id == id }) else { return }
        metadataRequests.insert(id)
        guard metadataTask == nil else { return }
        metadataTask = Task { [weak self] in
            guard let self else { return }
            defer { self.metadataTask = nil }
            while !self.metadataRequests.isEmpty {
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                let ids = self.metadataRequests
                self.metadataRequests.removeAll()
                for id in ids { await self.refreshMetadata(id) }
            }
        }
    }

    private func refreshMetadata(_ id: String) async {
        guard let original = threads.first(where: { $0.id == id }), enabledProviders.contains(original.provider) else { return }
        let revision = revisions[id, default: 0]
        do {
            let updated: AgentThread?
            switch original.provider {
            case .codex: updated = try await codex.readThread(original.sessionID)
            case .claude: updated = try await ClaudeIntegration.readThread(original.sessionID)
            }
            guard var updated, enabledProviders.contains(original.provider),
                  let index = threads.firstIndex(where: { $0.id == id }) else { return }
            if revisions[id, default: 0] != revision {
                requestMetadata(id)
                return
            }
            if original.provider == .claude { updated.status = claudeStatuses[id] ?? .unknown }
            threads[index] = reconcile(updated)
            revisions[id, default: 0] += 1
            errors[original.provider] = nil
            saveActivity()
        } catch {
            if enabledProviders.contains(original.provider) { errors[original.provider] = error.localizedDescription }
        }
    }

    @discardableResult
    func settle(_ thread: AgentThread) -> AgentThread? {
        settledThreadIDs.insert(thread.id)
        defaults.set(settledThreadIDs.sorted(), forKey: "integration.settledThreadIDs")
        let draft = drafts.removeValue(forKey: thread.id)
        claudeStatuses[thread.id] = nil
        metadataRequests.remove(thread.id)
        if viewedThreadID == thread.id { viewedThreadID = nil }
        return draft
    }

    func restore(_ thread: AgentThread, draft: AgentThread? = nil) {
        settledThreadIDs.remove(thread.id)
        defaults.set(settledThreadIDs.sorted(), forKey: "integration.settledThreadIDs")
        if let draft { drafts[thread.id] = draft }
        if !threads.contains(where: { $0.id == thread.id }) {
            threads.append(reconcile(thread))
        }
    }

    func markUnread(_ thread: AgentThread) async {
        guard thread.provider == .codex, let readState = thread.readState else { return }
        do {
            let updated = try await codex.markUnread(threadID: thread.sessionID, revision: readState.revision)
            guard let index = threads.firstIndex(where: { $0.id == thread.id }) else { return }
            if viewedThreadID == thread.id { viewedThreadID = nil }
            activity[thread.id]?.clearReadRevision()
            var latest = threads[index]
            latest.readState = updated
            threads[index] = reconcile(latest)
            revisions[thread.id, default: 0] += 1
            saveActivity()
        } catch { actionError = error.localizedDescription }
    }

    func setViewedThread(_ id: String?) {
        viewedThreadID = id
        guard let index = threads.firstIndex(where: { $0.id == id }) else { return }
        activity[threads[index].id]?.markRead(threads[index])
        threads[index].hasUnreadResult = false
        saveActivity()
    }

    private func reconcile(_ thread: AgentThread, now: Date = .now) -> AgentThread {
        var thread = thread
        if thread.provider == .claude, !thread.hasProviderTitle, let title = terminalTitles[thread.id] {
            thread.title = title
        }
        var state = activity[thread.id] ?? ThreadActivity(thread: thread)
        let result = state.update(thread, isViewed: viewedThreadID == thread.id, now: now)
        activity[thread.id] = state
        return result
    }

    /// Task terminals run a known provider via exec, so they don't depend on shell preexec hooks.
    func recordTerminalTitle(_ reportedTitle: String, threadID: String) {
        guard !settledThreadIDs.contains(threadID),
              let index = threads.firstIndex(where: { $0.id == threadID }),
              enabledProviders.contains(threads[index].provider) else { return }
        let thread = threads[index]
        // Codex's default OSC title describes its project/status. Use its RPC
        // name/status/turn events for conversation metadata instead.
        guard thread.provider == .claude else { return }
        guard let title = AgentTerminalTitle.displayTitle(
            reportedTitle: reportedTitle, foregroundCommand: thread.provider.rawValue
        ) else { return }
        guard terminalTitles[threadID] != title else { return }
        terminalTitles[threadID] = title
        defaults.set(terminalTitles, forKey: "integration.terminalTitles")
        if !thread.hasProviderTitle {
            var updated = thread
            updated.title = title
            threads[index] = updated
            if drafts[threadID] != nil { drafts[threadID] = updated }
            revisions[threadID, default: 0] += 1
        }
        // Renaming in the CLI may update its saved name as well as its OSC title.
        requestMetadata(threadID)
    }

    private func saveActivity() {
        if let data = try? JSONEncoder().encode(activity) {
            defaults.set(data, forKey: "integration.threadActivity")
        }
    }

    func refresh() async {
        refreshRequested = true
        if let refreshTask { await refreshTask.value; return }
        isRefreshing = true
        let task = Task {
            repeat {
                refreshRequested = false
                async let codexRefresh: Void = refresh(.codex)
                async let claudeRefresh: Void = refresh(.claude)
                _ = await (codexRefresh, claudeRefresh)
            } while refreshRequested
        }
        refreshTask = task
        await task.value
        refreshTask = nil
        isRefreshing = false
    }

    private func refresh(_ provider: AgentProvider) async {
        guard enabledProviders.contains(provider) else {
            errors[provider] = nil
            if provider == .codex { codex.close() }
            return
        }
        let initialRevisions = revisions
        do {
            let latest: [AgentThread]
            switch provider {
            case .codex: latest = try await codex.listThreads()
            case .claude: latest = try await ClaudeIntegration.listThreads()
            }
            try Task.checkCancellation()
            guard enabledProviders.contains(provider) else { return }
            let listedIDs = Set(latest.map(\.id))
            var unlisted: [AgentThread] = []
            for (id, draft) in drafts where draft.provider == provider {
                if listedIDs.contains(id) {
                    drafts[id] = nil
                    continue
                }
                unlisted.append(draft)
            }
            let incoming = latest + unlisted
            let incomingIDs = Set(incoming.map(\.id))
            let changed = threads.filter {
                $0.provider == provider && revisions[$0.id, default: 0] != initialRevisions[$0.id, default: 0]
            }
            let reconciled = incoming.map { source in
                if let current = changed.first(where: { $0.id == source.id }) { return current }
                var thread = source
                if provider == .claude { thread.status = claudeStatuses[thread.id] ?? .unknown }
                return reconcile(thread)
            } + changed.filter { !incomingIDs.contains($0.id) }
            saveActivity()
            threads.removeAll { $0.provider == provider }
            threads.append(contentsOf: reconciled)
            errors[provider] = nil
        } catch is CancellationError {
        } catch {
            guard enabledProviders.contains(provider) else { return }
            errors[provider] = error.localizedDescription
            for index in threads.indices where threads[index].provider == provider {
                threads[index].status = .unknown
            }
        }
    }

    func createThread(provider: AgentProvider, directory: String) async throws -> AgentThread {
        switch provider {
        case .codex: try await codex.startThread(directory: directory)
        case .claude:
            AgentThread(sessionID: UUID().uuidString.lowercased(), provider: .claude, title: "New Claude thread", directory: directory, updatedAt: .now, status: .idle)
        }
    }

    func registerDraft(_ thread: AgentThread) {
        drafts[thread.id] = thread
        // A creation event may have already refreshed this thread into the list.
        if !threads.contains(where: { $0.id == thread.id }) {
            threads.insert(reconcile(thread), at: 0)
        }
        saveActivity()
    }

    func prepareCommand(for thread: AgentThread, isNew: Bool = false) async throws -> String {
        guard UUID(uuidString: thread.sessionID) != nil else { throw IntegrationError(message: "Invalid session identifier.") }
        switch thread.provider {
        case .codex:
            try await codex.connect()
            guard let socketPath = codex.socketPath else { throw IntegrationError(message: "Codex is disconnected. Try again.") }
            return "codex --remote \(IntegrationProcess.quote("unix://" + socketPath)) resume \(IntegrationProcess.quote(thread.sessionID))"
        case .claude:
            let settings = try await claudeHooks.settings()
            claudeStatuses[thread.id] = .idle
            return "claude \(isNew || drafts[thread.id] != nil ? "--session-id" : "--resume") \(IntegrationProcess.quote(thread.sessionID)) --settings \(IntegrationProcess.quote(settings))"
        }
    }

    func recordProcessExit(threadID: String, code: Int32?) {
        guard !settledThreadIDs.contains(threadID), let index = threads.firstIndex(where: { $0.id == threadID }) else { return }
        var thread = threads[index]
        if let code, code != 0 { thread.status = .failed }
        else if thread.status != .done { thread.status = .stopped }
        if thread.provider == .claude { claudeStatuses[threadID] = thread.status }
        if drafts[threadID] != nil { drafts[threadID] = thread }
        threads[index] = reconcile(thread)
        revisions[threadID, default: 0] += 1
        saveActivity()
    }
}
