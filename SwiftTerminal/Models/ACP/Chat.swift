import Foundation
import Observation
import ACP

@Observable
final class Chat: Identifiable, Hashable, Codable {
    var id = UUID()
    var title: String = "New Chat"
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

    var isActive: Bool { session.isConnected }

    private var checkpointNamespace: String { id.uuidString }

    init(title: String = "New Chat", provider: AgentProvider = .codex, sortOrder: Int = 0) {
        self.title = title
        self.provider = provider
        self.sortOrder = sortOrder
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, title, provider, date, sortOrder, turnCount
        case messages, checkpoints
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
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
        wireLiveCallbacks()
        session.connect(workingDirectory: directory)
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
        session.onConnected = nil
        session.disconnect()
    }

    // MARK: - Live Callbacks

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

            guard let dir = self.workspace?.directory else { return }

            do {
                let snapshots = try await CheckpointService.captureCheckpoint(
                    workspace: URL(fileURLWithPath: dir),
                    sessionId: self.checkpointNamespace,
                    turn: self.turnCount
                )
                var checkpoint = Checkpoint(turnIndex: self.turnCount)
                checkpoint.repoSnapshots = snapshots
                self.checkpoints.append(checkpoint)
            } catch {
                print("[Checkpoint] capture failed: \(error.localizedDescription)")
            }
        }

        session.onConnected = { [weak self] in
            guard let self else { return }
            self.date = Date()
            self.scheduleSave()

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
                            sessionId: self.checkpointNamespace,
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

        if let dir = workspace?.directory {
            await CheckpointService.deleteCheckpoints(
                workspace: URL(fileURLWithPath: dir),
                sessionId: checkpointNamespace,
                afterTurn: restoreToTurn,
                throughTurn: turnCount
            )
        }

        turnCount = restoreToTurn
        date = Date()
        session.disconnect()
        session = ACPSession()
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
