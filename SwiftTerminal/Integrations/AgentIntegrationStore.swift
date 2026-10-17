import Foundation
import Observation

/// Observable UI facade. Shared task state lives here; provider behavior lives in adapters.
@MainActor
@Observable
final class AgentIntegrationStore {
    let providers: [AgentProvider]
    private(set) var threads: [AgentThread] = []
    private(set) var errors: [AgentProvider: String] = [:]
    private(set) var isRefreshing = false
    private(set) var deletingThreadIDs: Set<String> = []
    private(set) var deletedThreadIDs: Set<String> = []
    var actionError: String?
    private(set) var settledThreadIDs: Set<String>
    private var enabled: Set<AgentProvider>
    private var activity: [String: ThreadActivity]
    @ObservationIgnored private var viewedThreadID: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let adapters: [AgentProvider: any AgentProviderAdapter]
    // Results from a previous enablement must not update a newly enabled connection.
    @ObservationIgnored private var generations: [AgentProvider: Int] = [:]
    @ObservationIgnored private var revisions: [String: Int] = [:]
    @ObservationIgnored private var metadataRequests: Set<String> = []
    @ObservationIgnored private var metadataTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshRequested = false
    @ObservationIgnored private var drafts: [String: AgentThread] = [:]
    @ObservationIgnored private var terminalTitles: [String: String]

    var enabledProviders: [AgentProvider] { providers.filter { enabled.contains($0) } }
    var isEnabled: Bool { !enabled.isEmpty }
    var visibleThreads: [AgentThread] {
        threads.filter { enabled.contains($0.provider) }
            .sorted(by: AgentThread.newestFirst)
    }

    init(adapters: [any AgentProviderAdapter], defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.adapters = Dictionary(uniqueKeysWithValues: adapters.map { ($0.provider, $0) })
        providers = adapters.map(\.provider)
        enabled = Set(providers.filter { defaults.bool(forKey: $0.settingsKey) })
        terminalTitles = defaults.dictionary(forKey: "integration.terminalTitles") as? [String: String] ?? [:]
        settledThreadIDs = Set(defaults.stringArray(forKey: "integration.settledThreadIDs") ?? [])
        activity = defaults.data(forKey: "integration.threadActivity")
            .flatMap { try? JSONDecoder().decode([String: ThreadActivity].self, from: $0) } ?? [:]
        for adapter in adapters {
            let provider = adapter.provider
            adapter.onEvent = { [weak self] event in self?.receive(event, from: provider) }
        }
    }

    subscript(isEnabled provider: AgentProvider) -> Bool {
        get { enabled.contains(provider) }
        set {
            guard adapters[provider] != nil, newValue != enabled.contains(provider) else { return }
            if newValue { enabled.insert(provider) }
            else { enabled.remove(provider) }
            defaults.set(newValue, forKey: provider.settingsKey)
            generations[provider, default: 0] += 1
            errors[provider] = nil
            adapters[provider]?.setEnabled(newValue)
            if !newValue {
                for index in threads.indices where threads[index].provider == provider {
                    threads[index].status = .unknown
                }
            }
        }
    }

    func canMarkUnread(_ thread: AgentThread) -> Bool {
        enabled.contains(thread.provider) && thread.readState != nil && !deletingThreadIDs.contains(thread.id)
            && adapters[thread.provider]?.capabilities.contains(.markUnread) == true
    }

    func supportsDeletion(_ thread: AgentThread) -> Bool {
        adapters[thread.provider]?.capabilities.contains(.deleteThread) == true
    }

    func canDelete(_ thread: AgentThread) -> Bool {
        enabled.contains(thread.provider) && supportsDeletion(thread)
            && !deletingThreadIDs.contains(thread.id) && !deletedThreadIDs.contains(thread.id)
    }

    func deletionMessage(for thread: AgentThread) -> String {
        let scope = adapters[thread.provider]?.capabilities.contains(.deleteDescendants) == true
            ? "This permanently deletes this thread and any child threads it created."
            : "This permanently deletes this thread and its associated agent history."
        return "\(scope) Open tasks for deleted threads will be stopped. This cannot be undone."
    }

    /// The controller stops this app's terminal before the provider removes its saved history.
    func deleteThread(_ thread: AgentThread) async {
        guard canDelete(thread), let adapter = adapters[thread.provider] else { return }
        deletingThreadIDs.insert(thread.id)
        defer { deletingThreadIDs.remove(thread.id) }
        do {
            try await adapter.deleteThread(thread)
            removeDeletedThread(thread.id)
        } catch {
            // A provider notification can confirm deletion before its RPC connection closes.
            if !deletedThreadIDs.contains(thread.id) { actionError = error.localizedDescription }
        }
    }

    private func removeDeletedThread(_ id: String) {
        guard deletedThreadIDs.insert(id).inserted else { return }
        threads.removeAll { $0.id == id }
        drafts[id] = nil
        activity[id] = nil
        terminalTitles[id] = nil
        metadataRequests.remove(id)
        settledThreadIDs.remove(id)
        revisions[id, default: 0] += 1
        if viewedThreadID == id { viewedThreadID = nil }
        defaults.set(terminalTitles, forKey: "integration.terminalTitles")
        defaults.set(settledThreadIDs.sorted(), forKey: "integration.settledThreadIDs")
        saveActivity()
    }

    private func receive(_ event: AgentEvent, from provider: AgentProvider) {
        switch event {
        case .threadUpdated(let sessionID, let update):
            guard enabled.contains(provider) else { return }
            guard let index = threads.firstIndex(where: { $0.provider == provider && $0.sessionID == sessionID }) else { return }
            let thread = reconcile(update.applying(to: threads[index]))
            threads[index] = thread
            if drafts[thread.id] != nil { drafts[thread.id] = thread }
            revisions[thread.id, default: 0] += 1
            saveActivity()
        case .threadInvalidated(let sessionID):
            guard enabled.contains(provider) else { return }
            requestMetadata("\(provider.rawValue):\(sessionID)")
        case .listInvalidated:
            guard enabled.contains(provider) else { return }
            Task { await refresh() }
        case .threadDeleted(let sessionID):
            removeDeletedThread("\(provider.rawValue):\(sessionID)")
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
        guard let original = threads.first(where: { $0.id == id }), enabled.contains(original.provider),
              let adapter = adapters[original.provider] else { return }
        let generation = generations[original.provider, default: 0]
        let revision = revisions[id, default: 0]
        do {
            guard let updated = try await adapter.readThread(original.sessionID),
                  isCurrent(original.provider, generation: generation),
                  let index = threads.firstIndex(where: { $0.id == id }) else { return }
            if revisions[id, default: 0] != revision {
                requestMetadata(id)
                return
            }
            threads[index] = reconcile(updated)
            revisions[id, default: 0] += 1
            errors[original.provider] = nil
            saveActivity()
        } catch is CancellationError {
        } catch {
            if isCurrent(original.provider, generation: generation), !deletedThreadIDs.contains(id), !deletingThreadIDs.contains(id) {
                errors[original.provider] = error.localizedDescription
            }
        }
    }

    @discardableResult
    func settle(_ thread: AgentThread) -> AgentThread? {
        guard !deletedThreadIDs.contains(thread.id), !deletingThreadIDs.contains(thread.id) else { return nil }
        settledThreadIDs.insert(thread.id)
        defaults.set(settledThreadIDs.sorted(), forKey: "integration.settledThreadIDs")
        let draft = drafts.removeValue(forKey: thread.id)
        adapters[thread.provider]?.forgetThread(thread.sessionID)
        metadataRequests.remove(thread.id)
        revisions[thread.id, default: 0] += 1
        if viewedThreadID == thread.id { viewedThreadID = nil }
        return draft
    }

    func restore(_ thread: AgentThread, draft: AgentThread? = nil) {
        guard !deletedThreadIDs.contains(thread.id), !deletingThreadIDs.contains(thread.id) else { return }
        settledThreadIDs.remove(thread.id)
        defaults.set(settledThreadIDs.sorted(), forKey: "integration.settledThreadIDs")
        if let draft { drafts[thread.id] = draft }
        if !threads.contains(where: { $0.id == thread.id }) {
            threads.append(reconcile(thread))
        }
        revisions[thread.id, default: 0] += 1
    }

    func markUnread(_ thread: AgentThread) async {
        guard canMarkUnread(thread), let adapter = adapters[thread.provider] else { return }
        let generation = generations[thread.provider, default: 0]
        do {
            let updated = try await adapter.markUnread(thread)
            guard isCurrent(thread.provider, generation: generation),
                  let index = threads.firstIndex(where: { $0.id == thread.id }) else { return }
            if viewedThreadID == thread.id { viewedThreadID = nil }
            activity[thread.id]?.clearReadRevision()
            var latest = threads[index]
            latest.readState = updated
            threads[index] = reconcile(latest)
            revisions[thread.id, default: 0] += 1
            saveActivity()
        } catch is CancellationError {
        } catch {
            if isCurrent(thread.provider, generation: generation) { actionError = error.localizedDescription }
        }
    }

    func setViewedThread(_ id: String?) {
        viewedThreadID = id
        guard let index = threads.firstIndex(where: { $0.id == id }) else { return }
        activity[threads[index].id]?.markRead(threads[index])
        threads[index].hasUnreadResult = false
        saveActivity()
    }

    private func reconcile(_ source: AgentThread, now: Date = .now) -> AgentThread {
        var thread = source
        if !thread.hasProviderTitle, let title = terminalTitles[thread.id] { thread.title = title }
        var state = activity[thread.id] ?? ThreadActivity(thread: thread)
        let result = state.update(thread, isViewed: viewedThreadID == thread.id,
                                  policy: adapters[thread.provider]?.activityPolicy ?? .providerTimestamp, now: now)
        activity[thread.id] = state
        return result
    }

    func recordTerminalTitle(_ reportedTitle: String, threadID: String) {
        guard !settledThreadIDs.contains(threadID),
              let index = threads.firstIndex(where: { $0.id == threadID }),
              enabled.contains(threads[index].provider),
              let title = adapters[threads[index].provider]?.title(from: reportedTitle),
              terminalTitles[threadID] != title else { return }
        terminalTitles[threadID] = title
        defaults.set(terminalTitles, forKey: "integration.terminalTitles")
        if !threads[index].hasProviderTitle {
            threads[index].title = title
            if drafts[threadID] != nil { drafts[threadID] = threads[index] }
            revisions[threadID, default: 0] += 1
        }
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
                await withTaskGroup(of: Void.self) { group in
                    for provider in providers {
                        group.addTask { await self.refresh(provider) }
                    }
                }
            } while refreshRequested
        }
        refreshTask = task
        await task.value
        refreshTask = nil
        isRefreshing = false
    }

    private func refresh(_ provider: AgentProvider) async {
        guard enabled.contains(provider), let adapter = adapters[provider] else { return }
        let generation = generations[provider, default: 0]
        let initialRevisions = revisions
        do {
            let listed = try await adapter.listThreads()
            try Task.checkCancellation()
            guard isCurrent(provider, generation: generation) else { return }
            // A list request started before deletion may still contain its old snapshot.
            let latest = listed.filter { !deletedThreadIDs.contains($0.id) }
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
                changed.first(where: { $0.id == source.id }) ?? reconcile(source)
            } + changed.filter { !incomingIDs.contains($0.id) }
            saveActivity()
            threads.removeAll { $0.provider == provider }
            threads.append(contentsOf: reconciled)
            errors[provider] = nil
        } catch is CancellationError {
        } catch {
            guard isCurrent(provider, generation: generation) else { return }
            errors[provider] = error.localizedDescription
            for index in threads.indices where threads[index].provider == provider {
                threads[index].status = .unknown
            }
        }
    }

    func createThread(provider: AgentProvider, directory: String) async throws -> AgentThread {
        let adapter = try enabledAdapter(for: provider)
        let generation = generations[provider, default: 0]
        let thread = try await adapter.createThread(directory: directory)
        try Task.checkCancellation()
        guard isCurrent(provider, generation: generation) else { throw CancellationError() }
        return thread
    }

    func registerDraft(_ thread: AgentThread) {
        // A creation event may have already refreshed this thread into the list.
        if let current = threads.first(where: { $0.id == thread.id }) {
            drafts[thread.id] = current
        } else {
            let draft = reconcile(thread)
            drafts[thread.id] = draft
            threads.insert(draft, at: 0)
        }
        revisions[thread.id, default: 0] += 1
        saveActivity()
    }

    func prepareLaunch(for thread: AgentThread, isNew: Bool = false) async throws -> AgentLaunch {
        let adapter = try enabledAdapter(for: thread.provider)
        let generation = generations[thread.provider, default: 0]
        let intent: AgentLaunchIntent = isNew || drafts[thread.id] != nil ? .create : .resume
        let launch = try await adapter.prepareLaunch(for: thread, intent: intent)
        try Task.checkCancellation()
        guard isCurrent(thread.provider, generation: generation) else { throw CancellationError() }
        return launch
    }

    func recordProcessExit(threadID: String, code: Int32?) {
        guard !settledThreadIDs.contains(threadID), let index = threads.firstIndex(where: { $0.id == threadID }) else { return }
        var thread = threads[index]
        if let code, code != 0 { thread.status = .failed }
        else if thread.status != .done { thread.status = .stopped }
        adapters[thread.provider]?.didExit(thread)
        if drafts[threadID] != nil { drafts[threadID] = thread }
        threads[index] = reconcile(thread)
        revisions[threadID, default: 0] += 1
        saveActivity()
    }

    private func enabledAdapter(for provider: AgentProvider) throws -> any AgentProviderAdapter {
        guard enabled.contains(provider), let adapter = adapters[provider] else {
            throw IntegrationError(message: "Enable \(provider.name) in Settings to open tasks.")
        }
        return adapter
    }

    private func isCurrent(_ provider: AgentProvider, generation: Int) -> Bool {
        enabled.contains(provider) && generations[provider, default: 0] == generation
    }
}
