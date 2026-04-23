import Foundation
import Observation
import ACP

@Observable
final class Chat: Identifiable, Hashable, Codable {
    var id = UUID()
    var title: String = "New Chat"
    var acpSessionId: String?
    var provider: AgentProvider = .codex
    var date: Date = Date()
    var sortOrder: Int = 0
    var turnCount: Int = 0

    private(set) var messages: [Message] = []
    private(set) var checkpoints: [Checkpoint] = []

    @ObservationIgnored
    weak var workspace: Workspace?

    @ObservationIgnored
    var session = ACPSession()

    @ObservationIgnored
    private var currentTurnMessage: Message?

    @ObservationIgnored
    var pendingInput: String?

    var prompt: String = ""

    // Replay state
    @ObservationIgnored
    private var replayTurn = 0

    @ObservationIgnored
    private var replayAssistant: Message?

    @ObservationIgnored
    private var replaySawUser = false

    @ObservationIgnored
    private var isReplaying = false

    var isActive: Bool { session.isConnected }

    init(title: String = "New Chat", provider: AgentProvider = .codex, sortOrder: Int = 0) {
        self.title = title
        self.provider = provider
        self.sortOrder = sortOrder
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, title, acpSessionId, provider, date, sortOrder, turnCount
        case messages, checkpoints
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.acpSessionId = try c.decodeIfPresent(String.self, forKey: .acpSessionId)
        self.provider = try c.decodeIfPresent(AgentProvider.self, forKey: .provider) ?? .codex
        self.date = try c.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        self.sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        self.turnCount = try c.decodeIfPresent(Int.self, forKey: .turnCount) ?? 0
        self.messages = try c.decodeIfPresent([Message].self, forKey: .messages) ?? []
        self.checkpoints = try c.decodeIfPresent([Checkpoint].self, forKey: .checkpoints) ?? []
        for msg in messages { msg.chat = self }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(acpSessionId, forKey: .acpSessionId)
        try c.encode(provider, forKey: .provider)
        try c.encode(date, forKey: .date)
        try c.encode(sortOrder, forKey: .sortOrder)
        try c.encode(turnCount, forKey: .turnCount)
        try c.encode(messages, forKey: .messages)
        try c.encode(checkpoints, forKey: .checkpoints)
    }

    // MARK: - Hashable

    static func == (lhs: Chat, rhs: Chat) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    // MARK: - Connection Lifecycle

    func connectIfNeeded() {
        guard !session.isConnected && !session.isConnecting else { return }
        guard let directory = workspace?.directory else { return }

        session.provider = provider

        if let acpId = acpSessionId {
            // Existing session: reconnect using our persisted state.
            // Discard the agent's replay stream — our stored messages are authoritative.
            isReplaying = true
            wireReconnectCallbacks()
            session.setWorkingDirectory(directory)
            Task {
                await session.relaunchAndLoadSession(SessionId(acpId))
                // Let any in-flight replay notifications drain before wiring live handlers.
                try? await Task.sleep(for: .seconds(1))
                self.isReplaying = false
                self.wireLiveCallbacks()
                if let text = self.pendingInput {
                    self.pendingInput = nil
                    self.session.send(text)
                }
            }
        } else {
            // New session
            wireLiveCallbacks()
            session.connect(workingDirectory: directory)
        }
    }

    /// Callbacks used while reconnecting to a tracked session. All agent-emitted
    /// replay content is dropped; only session-id changes are tracked.
    private func wireReconnectCallbacks() {
        session.onSessionUpdate = nil
        session.onTurnComplete = nil
        session.onTitleChanged = nil
        session.onSessionIdChanged = { [weak self] newId in
            guard let self else { return }
            if self.acpSessionId != newId {
                self.acpSessionId = newId
                self.date = Date()
                self.scheduleSave()
            }
        }
    }

    func sendMessage(_ text: String) {
        let pm = Message(role: .user, turnIndex: turnCount + 1)
        pm.blocks = [MessageBlock(type: .text, text: text)]
        pm.chat = self
        messages.append(pm)

        if session.isConnected {
            session.send(text)
        } else {
            pendingInput = text
            connectIfNeeded()
        }
        scheduleSave()
    }

    func disconnect() {
        session.onTurnComplete = nil
        session.onSessionUpdate = nil
        session.disconnect()
    }

    /// Create a Chat from an existing ACP session. Launches the agent,
    /// replays all notifications, and reconstructs messages.
    static func loadSession(
        sessionInfo: SessionInfo,
        provider: AgentProvider,
        workspace: Workspace
    ) async throws -> Chat {
        let chat = Chat(
            title: sessionInfo.title ?? "Imported Chat",
            provider: provider,
            sortOrder: workspace.chats.count
        )
        chat.workspace = workspace
        chat.acpSessionId = sessionInfo.sessionId.value
        chat.isReplaying = true
        chat.replayTurn = 0

        chat.session.provider = provider
        chat.session.setWorkingDirectory(workspace.directory)
        chat.wireReplayCallbacks()

        let client = try await chat.session.launchAndInitialize()
        chat.session.listenForNotifications(client: client)

        let response = try await client.loadSession(
            sessionId: sessionInfo.sessionId,
            cwd: workspace.directory,
            mcpServers: []
        )

        chat.session.setSessionId(response.sessionId ?? sessionInfo.sessionId)
        chat.session.isConnected = true
        chat.session.isConnecting = false

        // Give notification stream time to finish replaying
        try? await Task.sleep(for: .seconds(1))

        chat.finalizeReplay()
        return chat
    }

    // MARK: - Replay Handlers

    private func wireReplayCallbacks() {
        session.onSessionUpdate = { [weak self] update in
            self?.handleReplayUpdate(update)
        }

        session.onTurnComplete = { [weak self] in
            guard let self else { return }
            self.replayTurn += 1
            self.replayAssistant = nil
            self.replaySawUser = false
        }

        session.onSessionIdChanged = { [weak self] newId in
            guard let self else { return }
            if self.acpSessionId != newId {
                self.acpSessionId = newId
                self.date = Date()
            }
        }

        session.onTitleChanged = { [weak self] newTitle in
            self?.title = newTitle
        }
    }

    private func handleReplayUpdate(_ update: SessionUpdate) {
        switch update {
        case .userMessageChunk(let content):
            if case .text(let tc) = content {
                if !replaySawUser {
                    if replayAssistant != nil {
                        replayTurn += 1
                        replayAssistant = nil
                    }
                    let userMsg = Message(role: .user, turnIndex: replayTurn + 1)
                    userMsg.chat = self
                    userMsg.blocks = [MessageBlock(type: .text, text: tc.text)]
                    messages.append(userMsg)
                    replaySawUser = true
                } else {
                    if let last = messages.last, last.role == .user {
                        last.appendToLastBlock(ofType: .text, text: tc.text)
                    }
                }
            }
        case .agentMessageChunk(let content):
            if case .text(let tc) = content {
                replaySawUser = false
                if replayAssistant == nil {
                    let msg = Message(role: .assistant, turnIndex: replayTurn + 1)
                    msg.chat = self
                    messages.append(msg)
                    replayAssistant = msg
                }
                replayAssistant?.appendToLastBlock(ofType: .text, text: tc.text)
            }
        case .agentThoughtChunk(let content):
            if case .text(let tc) = content {
                replaySawUser = false
                if replayAssistant == nil {
                    let msg = Message(role: .assistant, turnIndex: replayTurn + 1)
                    msg.chat = self
                    messages.append(msg)
                    replayAssistant = msg
                }
                replayAssistant?.appendToLastBlock(ofType: .thought, text: tc.text)
            }
        case .toolCall(let toolUpdate):
            replaySawUser = false
            if replayAssistant == nil {
                let msg = Message(role: .assistant, turnIndex: replayTurn + 1)
                msg.chat = self
                messages.append(msg)
                replayAssistant = msg
            }
            replayAssistant?.addToolCall(
                toolCallId: toolUpdate.toolCallId,
                title: toolUpdate.title ?? toolUpdate.kind?.rawValue.capitalized ?? "Tool",
                kind: toolUpdate.kind,
                status: toolUpdate.status ?? .completed,
                diff: Self.firstDiff(in: toolUpdate.content)
            )
        case .toolCallUpdate(let details):
            replayAssistant?.updateToolCall(
                id: details.toolCallId,
                title: details.title,
                kind: details.kind,
                status: details.status,
                diff: details.content.flatMap(Self.firstDiff)
            )
        case .sessionInfoUpdate(let info):
            if let newTitle = info.title {
                title = newTitle
            }
        default:
            break
        }
    }

    private func finalizeReplay() {
        if replayAssistant != nil {
            replayTurn += 1
        }
        turnCount = replayTurn
        isReplaying = false
        replayAssistant = nil
        replaySawUser = false
        currentTurnMessage = nil

        wireLiveCallbacks()

        // Handle pending input after replay
        if let text = pendingInput {
            pendingInput = nil
            session.send(text)
        }
    }

    // MARK: - Live Callbacks (after replay or for new sessions)

    private func wireLiveCallbacks() {
        session.onSessionUpdate = { [weak self] update in
            self?.handleLiveUpdate(update)
        }

        session.onTurnComplete = { [weak self] in
            guard let self else { return }
            self.turnCount += 1
            self.date = Date()
            self.currentTurnMessage = nil
            self.scheduleSave()

            guard let dir = self.workspace?.directory,
                  let acpId = self.acpSessionId else { return }

            do {
                let snapshots = try await CheckpointService.captureCheckpoint(
                    workspace: URL(fileURLWithPath: dir),
                    sessionId: acpId,
                    turn: self.turnCount
                )
                var checkpoint = Checkpoint(turnIndex: self.turnCount)
                checkpoint.repoSnapshots = snapshots
                self.checkpoints.append(checkpoint)
            } catch {
                print("[Checkpoint] capture failed: \(error.localizedDescription)")
            }
        }

        session.onSessionIdChanged = { [weak self] newId in
            guard let self else { return }
            if self.acpSessionId != newId {
                self.acpSessionId = newId
                self.date = Date()
                self.scheduleSave()
            }

            if let text = self.pendingInput {
                self.pendingInput = nil
                self.session.send(text)
            }

            if self.turnCount == 0 && !self.checkpoints.contains(where: { $0.turnIndex == 0 }) {
                Task { [weak self] in
                    guard let self, let dir = self.workspace?.directory else { return }
                    do {
                        let snapshots = try await CheckpointService.captureCheckpoint(
                            workspace: URL(fileURLWithPath: dir),
                            sessionId: newId,
                            turn: 0
                        )
                        var checkpoint = Checkpoint(turnIndex: 0)
                        checkpoint.repoSnapshots = snapshots
                        self.checkpoints.append(checkpoint)
                    } catch {
                        print("[Checkpoint] baseline capture failed: \(error.localizedDescription)")
                    }
                }
            }
        }

        session.onTitleChanged = { [weak self] newTitle in
            self?.title = newTitle
        }
    }

    // MARK: - Live Update Handling

    private func getOrCreateTurnMessage() -> Message {
        if let existing = currentTurnMessage { return existing }
        let pm = Message(role: .assistant, turnIndex: turnCount + 1)
        pm.chat = self
        messages.append(pm)
        currentTurnMessage = pm
        return pm
    }

    private func handleLiveUpdate(_ update: SessionUpdate) {
        // Defense-in-depth: drop any late replay notifications that slip through
        // after wireLiveCallbacks has been re-attached.
        if isReplaying { return }

        switch update {
        case .userMessageChunk:
            break
        case .agentMessageChunk(let content):
            if case .text(let tc) = content {
                getOrCreateTurnMessage().appendToLastBlock(ofType: .text, text: tc.text)
            }
        case .agentThoughtChunk(let content):
            if case .text(let tc) = content {
                getOrCreateTurnMessage().appendToLastBlock(ofType: .thought, text: tc.text)
            }
        case .toolCall(let update):
            getOrCreateTurnMessage().addToolCall(
                toolCallId: update.toolCallId,
                title: update.title ?? update.kind?.rawValue.capitalized ?? "Tool",
                kind: update.kind,
                status: update.status ?? .pending,
                diff: Self.firstDiff(in: update.content)
            )
        case .toolCallUpdate(let details):
            getOrCreateTurnMessage().updateToolCall(
                id: details.toolCallId,
                title: details.title,
                kind: details.kind,
                status: details.status,
                diff: details.content.flatMap(Self.firstDiff)
            )
        default:
            break
        }
    }

    // MARK: - Revert

    func revert(toBeforeTurn turn: Int) async {
        guard turn >= 1, turn <= turnCount else { return }

        let revertedMsg = messages.first { $0.turnIndex == turn && $0.role == .user }
        prompt = revertedMsg?.text ?? ""

        messages.removeAll { $0.turnIndex >= turn }

        let restoreToTurn = turn - 1
        if let checkpoint = checkpoints.first(where: { $0.turnIndex == restoreToTurn }),
           let dir = workspace?.directory {
            do {
                try await CheckpointService.restoreCheckpoint(
                    workspace: URL(fileURLWithPath: dir),
                    snapshots: checkpoint.repoSnapshots
                )
            } catch {
                print("[Revert] filesystem restore failed: \(error.localizedDescription)")
            }
        }

        checkpoints.removeAll { $0.turnIndex >= turn }

        if let dir = workspace?.directory, let acpId = acpSessionId {
            await CheckpointService.deleteCheckpoints(
                workspace: URL(fileURLWithPath: dir),
                sessionId: acpId,
                afterTurn: restoreToTurn,
                throughTurn: turnCount
            )
        }

        turnCount = restoreToTurn
        date = Date()
        session.disconnect()
        session = ACPSession()
        acpSessionId = nil
        currentTurnMessage = nil

        scheduleSave()
        connectIfNeeded()
    }

    // MARK: - Persistence

    private func scheduleSave() {
        workspace?.store?.scheduleSave()
    }

    // MARK: - Helpers

    private static func firstDiff(in content: [ToolCallContent]) -> ToolCallDiff? {
        for item in content {
            if case .diff(let diff) = item { return diff }
        }
        return nil
    }
}
