import Foundation

/// A pending image attachment to send with the next message.
struct ImageAttachment: Identifiable {
    let id = UUID()
    let data: Data
    let mediaType: String

    var base64String: String { data.base64EncodedString() }

    var bridgePayload: [String: String] {
        ["mediaType": mediaType, "data": base64String]
    }
}

/// High-level service that orchestrates Claude via the Agent SDK bridge.
@Observable
final class ClaudeService {
    // MARK: - Public State

    let id = UUID()
    var prompt = ""
    var imageAttachments: [ImageAttachment] = []
    var messages: [ChatMessage] = []
    var isStreaming = false
    var session = SessionInfo()
    var error: String?
    var availableSessions: [SessionSummary] = []
    var pendingApproval: ApprovalRequest?
    var selectedModel: ModelOption = .opus
    var selectedEffort: EffortLevel = .medium
    var selectedContextWindow: ContextWindow = .extended

    // MARK: - Private

    let workspace: Workspace
    let claudeSession: ClaudeSession?
    var workingDirectory: String { workspace.directory }
    private var process: ClaudeProcess?
    private var readerTask: Task<Void, Never>?
    private var bridgeReady = false
    private(set) var queryActive = false

    @ObservationIgnored private var toolUseIndex: [String: BlockLocation] = [:]
    @ObservationIgnored private var state = StreamState()
    @ObservationIgnored private var turnContinuation: CheckedContinuation<Void, Never>?
    @ObservationIgnored private var bridgeReadyContinuations: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var responseContinuations: [String: CheckedContinuation<BridgeResponse?, Never>] = [:]
    /// Maps local ChatMessage ID → SDK user message UUID
    @ObservationIgnored private var userMessageUUIDs: [String: String] = [:]
    /// The local ID of the user message currently being sent (awaiting SDK UUID)
    @ObservationIgnored private var pendingUserMessageLocalID: String?
    /// SDK UUID of the most recent assistant message
    @ObservationIgnored private var lastAssistantSDKUUID: String?
    /// Maps local user message ID → SDK UUID of the assistant message preceding it
    @ObservationIgnored private var precedingAssistantUUID: [String: String] = [:]
    /// When set, next send() will pass resumeSessionAt to truncate conversation
    @ObservationIgnored private var pendingResumeAt: String?

    init(workspace: Workspace, claudeSession: ClaudeSession? = nil) {
        self.workspace = workspace
        self.claudeSession = claudeSession
        if let sdkID = claudeSession?.sdkSessionID {
            self.session.sessionID = sdkID
        }
    }

    deinit {
        process?.terminate()
        readerTask?.cancel()
    }

    // MARK: - Public API

    func sendMessage() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !imageAttachments.isEmpty, !isStreaming else { return }
        let images = imageAttachments
        prompt = ""
        imageAttachments = []
        send(trimmed.isEmpty ? " " : trimmed, images: images)
    }

    func send(_ text: String, images: [ImageAttachment] = []) {
        guard !isStreaming else { return }

        var blocks: [MessageBlock] = [.text(TextInfo(content: text))]
        for image in images {
            blocks.append(.image(ImageInfo(data: image.data, mediaType: image.mediaType)))
        }
        let userMessage = ChatMessage(role: .user, blocks: blocks)
        messages.append(userMessage)
        messages.append(ChatMessage(role: .assistant))
        state.reset()

        // Record preceding assistant UUID for this user message
        if let aUUID = lastAssistantSDKUUID {
            precedingAssistantUUID[userMessage.id] = aUUID
        }
        pendingUserMessageLocalID = userMessage.id

        isStreaming = true
        error = nil

        let imagePayloads = images.map(\.bridgePayload)

        Task { [weak self] in
            guard let self else { return }
            await self.ensureBridgeStarted()

            if !self.queryActive {
                var params: [String: Any] = [
                    "cwd": self.workingDirectory,
                    "permissionMode": self.session.permissionMode.rawValue,
                    "initialMessage": text,
                    "model": self.selectedModel.rawValue,
                    "effort": self.selectedEffort.rawValue,
                    "contextWindow": self.selectedContextWindow.rawValue,
                ]
                if !imagePayloads.isEmpty {
                    params["images"] = imagePayloads
                }
                if self._continueLastOnNextSend {
                    params["continueSession"] = true
                    self._continueLastOnNextSend = false
                } else if let resumeID = self.session.sessionID {
                    params["resume"] = resumeID
                }
                if let resumeAt = self.pendingResumeAt {
                    params["resumeSessionAt"] = resumeAt
                    self.pendingResumeAt = nil
                }
                self.process?.sendCommand("start_session", params: params)
                self.queryActive = true
            } else {
                var msgParams: [String: Any] = ["text": text]
                if !imagePayloads.isEmpty {
                    msgParams["images"] = imagePayloads
                }
                self.process?.sendCommand("send_message", params: msgParams)
            }

            await withCheckedContinuation { continuation in
                self.turnContinuation = continuation
            }
        }
    }

    func stop() {
        process?.sendCommand("interrupt")
        isStreaming = false
        pendingApproval = nil
        turnContinuation?.resume()
        turnContinuation = nil
    }

    /// Kill the background bridge process but keep all local messages and state.
    /// The process will auto-resume on next send/rewind.
    func disconnectProcess() {
        if queryActive {
            process?.sendCommand("stop")
        }
        process?.terminate()
        process = nil
        readerTask?.cancel()
        readerTask = nil
        bridgeReady = false
        queryActive = false
        isStreaming = false
        pendingApproval = nil
        turnContinuation?.resume()
        turnContinuation = nil
        for c in bridgeReadyContinuations { c.resume() }
        bridgeReadyContinuations.removeAll()
    }

    func clearSession() {
        // Stop current query but keep the bridge process alive for reuse
        if queryActive {
            process?.sendCommand("stop")
        }
        queryActive = false
        isStreaming = false

        prompt = ""
        imageAttachments = []
        messages.removeAll()
        session = SessionInfo()
        toolUseIndex.removeAll()
        state = StreamState()
        userMessageUUIDs.removeAll()
        precedingAssistantUUID.removeAll()
        lastAssistantSDKUUID = nil
        pendingUserMessageLocalID = nil
        pendingResumeAt = nil
        pendingApproval = nil
        _continueLastOnNextSend = false
        error = nil

        turnContinuation?.resume()
        turnContinuation = nil
    }

    // MARK: - Approval Flow

    func respondToApproval(allow: Bool, forSession: Bool = false) {
        guard let approval = pendingApproval else { return }
        pendingApproval = nil

        var params: [String: Any] = ["requestId": approval.requestId]

        if allow {
            params["behavior"] = "allow"
            if forSession {
                // Could pass updatedPermissions to allow for session
            }
        } else {
            params["behavior"] = "deny"
            params["message"] = "Denied by user"
        }

        process?.sendCommand("respond_to_approval", params: params)
    }

    // MARK: - Model & Settings

    func setModel(_ model: ModelOption) {
        selectedModel = model
        selectedContextWindow = model == .opus ? .extended : .standard
        if queryActive {
            process?.sendCommand("set_model", params: ["model": model.rawValue])
        }
    }

    func setPermissionMode(_ mode: PermissionModeOption) {
        session.permissionMode = mode
        if queryActive {
            process?.sendCommand("set_permission_mode", params: ["mode": mode.rawValue])
        }
    }

    // MARK: - Rewind

    /// Full rewind: reverts files, stops session, trims local messages,
    /// and puts the rewound user message text back into the prompt.
    func rewind(toMessageID messageID: String) async {
        guard let sdkUUID = userMessageUUIDs[messageID] else {
            error = "Cannot rewind: no SDK UUID for this message"
            return
        }

        // Find the message index and its text
        guard let msgIndex = messages.firstIndex(where: { $0.id == messageID }),
              messages[msgIndex].role == .user else {
            error = "Cannot rewind: message not found"
            return
        }
        let messageText = messages[msgIndex].text

        // 0. Ensure there's an active SDK session (needed after app reload)
        await ensureBridgeStarted()
        if !queryActive, let sessionID = session.sessionID {
            process?.sendCommand("activate_session", params: [
                "sessionId": sessionID,
                "cwd": workingDirectory,
                "permissionMode": session.permissionMode.rawValue
            ])
            let activateResp = await waitForBridgeResponse("activate_session")
            if activateResp?.success == true {
                queryActive = true
            } else {
                error = "Cannot rewind: failed to activate session"
                return
            }
        }

        // 1. Rewind files to state at this user message
        process?.sendCommand("rewind", params: [
            "userMessageId": sdkUUID
        ])

        let response = await waitForBridgeResponse("rewind")
        if let result = response?.result, result["canRewind"] as? Bool != true {
            error = result["error"] as? String ?? "Cannot rewind files"
            return
        }

        // 2. The bridge already stopped the session after rewind.
        //    Set up to resume at the preceding assistant message on next send.
        queryActive = false

        if let precedingUUID = precedingAssistantUUID[messageID] {
            pendingResumeAt = precedingUUID
        } else {
            // First user message — clear session entirely, start fresh
            session.sessionID = nil
        }

        // 3. Trim local messages: remove this user message and everything after
        let removedIDs = messages[msgIndex...].map(\.id)
        messages.removeSubrange(msgIndex...)

        // Clean up tool indices for removed messages
        for id in removedIDs {
            userMessageUUIDs.removeValue(forKey: id)
            precedingAssistantUUID.removeValue(forKey: id)
        }
        toolUseIndex = toolUseIndex.filter { $0.value.messageIndex < messages.count }

        // 4. Put the message text back into the prompt
        prompt = messageText

        // 5. Reset streaming state
        isStreaming = false
        pendingApproval = nil
        state.reset()
        turnContinuation?.resume()
        turnContinuation = nil
    }

    // MARK: - Session Management

    func listSessions() async {
        await ensureBridgeStarted()
        process?.sendCommand("list_sessions", params: [
            "cwd": workingDirectory,
            "limit": 50
        ])

        let response = await waitForBridgeResponse("list_sessions")
        if let sessions = response?.sessions {
            availableSessions = sessions.compactMap { dict in
                guard let id = dict["sessionId"] as? String else { return nil }
                return SessionSummary(
                    id: id,
                    title: dict["title"] as? String,
                    lastActive: dict["lastActive"] as? String,
                    messageCount: dict["messageCount"] as? Int ?? 0
                )
            }
        }
    }

    /// Resume a specific session by ID.
    func resumeSession(_ sessionID: String) {
        clearSession()

        Task { [weak self] in
            guard let self else { return }
            await self.ensureBridgeStarted()

            self.process?.sendCommand("get_session_messages", params: [
                "sessionId": sessionID,
                "cwd": self.workingDirectory
            ])

            let response = await self.waitForBridgeResponse("get_session_messages")
            if let rawMessages = response?.messages {
                self.restoreMessages(from: rawMessages)
            }

            self.session.sessionID = sessionID
        }
    }

    @ObservationIgnored private var _continueLastOnNextSend = false

    private func restoreMessages(from rawMessages: [[String: Any]]) {
        for raw in rawMessages {
            guard let type = raw["type"] as? String,
                  let message = raw["message"] as? [String: Any],
                  let contentArray = message["content"] as? [[String: Any]] else { continue }

            let role: MessageRole = type == "user" ? .user : .assistant

            var blocks: [MessageBlock] = []
            for block in contentArray {
                guard let blockType = block["type"] as? String else { continue }
                switch blockType {
                case "text":
                    if let text = block["text"] as? String, !text.isEmpty {
                        blocks.append(.text(TextInfo(content: text)))
                    }
                case "tool_use":
                    if let id = block["id"] as? String, let name = block["name"] as? String {
                        var input: [String: Any] = [:]
                        if let rawInput = block["input"] as? [String: Any] {
                            input = rawInput
                        }
                        let info = ToolUseInfo(id: id, name: name, input: input, result: nil, isComplete: true)
                        blocks.append(.toolUse(info))
                    }
                case "tool_result":
                    break
                case "thinking":
                    if let text = block["thinking"] as? String, !text.isEmpty {
                        blocks.append(.thinking(ThinkingInfo(text: text)))
                    }
                default:
                    break
                }
            }

            guard !blocks.isEmpty else { continue }

            let sdkUUID = raw["uuid"] as? String
            let msg = ChatMessage(role: role, blocks: blocks)

            if role == .user {
                if let uuid = sdkUUID {
                    userMessageUUIDs[msg.id] = uuid
                }
                // Record which assistant message precedes this user message
                if let aUUID = lastAssistantSDKUUID {
                    precedingAssistantUUID[msg.id] = aUUID
                }
            } else if role == .assistant {
                // Track the latest assistant UUID for precedingAssistantUUID mapping
                if let uuid = sdkUUID {
                    lastAssistantSDKUUID = uuid
                }
            }

            messages.append(msg)
        }
    }

    // MARK: - Bridge Lifecycle

    private func ensureBridgeStarted() async {
        if bridgeReady { return }

        if process != nil, process!.isRunning {
            // Process running but not ready yet - wait for bridge_ready
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                bridgeReadyContinuations.append(continuation)
            }
            return
        }

        let proc = ClaudeProcess()
        process = proc

        do {
            let lineStream = try proc.start(workingDirectory: workingDirectory)
            startReader(lineStream)

            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                bridgeReadyContinuations.append(continuation)
            }
        } catch {
            appendError("Failed to start bridge: \(error.localizedDescription)")
        }
    }

    private func startReader(_ lineStream: AsyncStream<String>) {
        readerTask?.cancel()
        readerTask = Task { [weak self] in
            for await line in lineStream {
                guard let self, !Task.isCancelled else { break }
                self.handleLine(line)
            }
            guard let self else { return }
            if self.isStreaming {
                self.error = "Bridge process disconnected"
            }
            self.isStreaming = false
            self.queryActive = false
            self.process = nil
            self.bridgeReady = false
            self.pendingApproval = nil
            self.turnContinuation?.resume()
            self.turnContinuation = nil
            for c in self.bridgeReadyContinuations { c.resume() }
            self.bridgeReadyContinuations.removeAll()
        }
    }

    // MARK: - Line Handling

    private func handleLine(_ line: String) {
        guard let event = StreamParser.parse(line) else { return }

        switch event {
        case .bridgeReady:
            bridgeReady = true
            for continuation in bridgeReadyContinuations {
                continuation.resume()
            }
            bridgeReadyContinuations.removeAll()

        case .bridgeResponse(let resp):
            // Capture SDK UUID for user messages from start_session/send_message responses
            if let uuid = resp.userMessageUUID, let localID = pendingUserMessageLocalID {
                userMessageUUIDs[localID] = uuid
                pendingUserMessageLocalID = nil
            }
            responseContinuations[resp.command]?.resume(returning: resp)
            responseContinuations.removeValue(forKey: resp.command)

        case .bridgeError(let err):
            self.error = err.error
            if let cmd = err.command {
                responseContinuations[cmd]?.resume(returning: nil)
                responseContinuations.removeValue(forKey: cmd)
            }

        case .sdkDone:
            // Query finished - clean up streaming state
            queryActive = false
            if isStreaming {
                isStreaming = false
                turnContinuation?.resume()
                turnContinuation = nil
            }

        case .system(let e):
            session.update(from: e)
            syncSessionID(session.sessionID)
            // Sync model selection with what the SDK reports
            if let detected = ModelOption.from(modelString: e.model) {
                selectedModel = detected
            }

        case .streamEvent(let delta):
            handleStreamDelta(delta)

        case .assistant(let e):
            handleAssistantEvent(e)

        case .user(let e):
            handleUserEvent(e)

        case .result(let e):
            handleResult(e)

        case .approvalRequest(let request):
            pendingApproval = request

        case .toolProgress(let progress):
            handleToolProgress(progress)

        case .sessionStateChanged(let stateEvent):
            session.state = stateEvent.state
            session.sessionID = stateEvent.sessionID
            syncSessionID(stateEvent.sessionID)

        case .statusUpdate(let statusEvent):
            session.isCompacting = statusEvent.status == "compacting"

        case .taskStarted, .taskProgress, .taskCompleted:
            break

        case .unknown:
            break
        }
    }

    // MARK: - Stream Delta Handling

    private func handleStreamDelta(_ delta: StreamDelta) {
        let msgIdx = currentAssistantIndex

        switch delta.eventType {
        case "content_block_start":
            guard let cb = delta.contentBlock, let index = delta.index else { return }
            switch cb.type {
            case "text":
                state.blockTexts[index] = ""
            case "tool_use":
                if let id = cb.id, let name = cb.name {
                    state.blockToolIDs[index] = id
                    if toolUseIndex[id] == nil {
                        let info = ToolUseInfo(id: id, name: name, input: [:])
                        let blockIdx = appendToolUseBlock(at: msgIdx, info: info)
                        toolUseIndex[id] = BlockLocation(messageIndex: msgIdx, blockIndex: blockIdx)
                    }
                }
            case "thinking":
                state.blockTexts[index] = ""
                state.thinkingBlockIndices.insert(index)
            default:
                break
            }

        case "content_block_delta":
            guard let d = delta.delta, let index = delta.index else { return }
            if d.type == "text_delta", let text = d.text {
                state.blockTexts[index, default: ""] += text
                updateTextBlock(at: msgIdx, text: state.blockTexts[index]!)
            } else if d.type == "input_json_delta", let json = d.partialJSON {
                state.toolInputJSON[index, default: ""] += json
            } else if d.type == "thinking_delta", let text = d.text {
                state.blockTexts[index, default: ""] += text
                updateThinkingBlock(at: msgIdx, text: state.blockTexts[index]!)
            }

        case "content_block_stop":
            guard let index = delta.index else { return }
            if let toolID = state.blockToolIDs[index],
               let jsonStr = state.toolInputJSON[index],
               let location = toolUseIndex[toolID] {
                updateToolUseInput(at: location, input: parseToolInput(jsonStr))
            }
            if state.thinkingBlockIndices.contains(index),
               let text = state.blockTexts[index], !text.isEmpty,
               !state.hasAddedThinking {
                appendThinkingBlock(at: msgIdx, text: text)
                state.hasAddedThinking = true
            }

        default:
            break
        }
    }

    // MARK: - Assistant Event Handling

    private func handleAssistantEvent(_ event: AssistantEvent) {
        let msg = event.message
        let msgID = msg.id

        if let msgID, msgID != state.lastMessageID {
            if state.lastMessageID != nil {
                messages.append(ChatMessage(role: .assistant))
                state.resetBlocks()
            }
            state.lastMessageID = msgID
        }

        for block in msg.content {
            switch block {
            case .toolUse(let toolBlock):
                let id = toolBlock.id
                if toolUseIndex[id] == nil {
                    let info = ToolUseInfo(
                        id: id,
                        name: toolBlock.name,
                        input: toolBlock.input.mapValues(\.value)
                    )
                    let blockIdx = appendToolUseBlock(at: currentAssistantIndex, info: info)
                    toolUseIndex[id] = BlockLocation(messageIndex: currentAssistantIndex, blockIndex: blockIdx)
                } else if let location = toolUseIndex[id] {
                    let input = toolBlock.input.mapValues(\.value)
                    if !input.isEmpty {
                        updateToolUseInput(at: location, input: input)
                    }
                }

            case .thinking(let thinkBlock):
                if !state.hasAddedThinking {
                    appendThinkingBlock(at: currentAssistantIndex, text: thinkBlock.thinking)
                    state.hasAddedThinking = true
                }

            case .text(let textBlock):
                if !state.hasStreamedText {
                    updateTextBlock(at: currentAssistantIndex, text: textBlock.text)
                }

            case .unknown:
                break
            }
        }

        if let sid = event.sessionID {
            session.sessionID = sid
            syncSessionID(sid)
        }

        // Track assistant SDK UUID for resumeSessionAt
        if let uuid = event.uuid {
            lastAssistantSDKUUID = uuid
        }
    }

    // MARK: - User Event Handling

    private func handleUserEvent(_ event: UserEvent) {
        for content in event.message.content {
            guard content.type == "tool_result",
                  let toolID = content.toolUseID else { continue }

            let resultText: String
            if let str = content.content?.stringValue {
                resultText = str
            } else if let dict = content.content?.dictValue {
                resultText = formatDict(dict)
            } else {
                resultText = ""
            }

            let resultInfo = ToolResultInfo(
                toolUseID: toolID,
                content: resultText,
                filePath: event.toolUseResult?.file?.filePath,
                numLines: event.toolUseResult?.file?.numLines
            )

            attachToolResult(toolID: toolID, result: resultInfo)
        }
    }

    // MARK: - Result Handling

    private func handleResult(_ event: ResultEvent) {
        session.update(from: event)
        syncSessionID(session.sessionID)

        let msgIdx = currentAssistantIndex
        if let resultText = event.result,
           !resultText.isEmpty,
           !state.hasStreamedText,
           messages[safe: msgIdx]?.text.isEmpty == true {
            updateTextBlock(at: msgIdx, text: resultText)
        }

        if event.isError == true {
            self.error = event.result
        }

        isStreaming = false
        pendingApproval = nil
        session.isCompacting = false
        turnContinuation?.resume()
        turnContinuation = nil
    }

    // MARK: - Tool Progress

    private func handleToolProgress(_ progress: ToolProgressEvent) {
        guard let location = toolUseIndex[progress.toolUseID],
              location.messageIndex < messages.count,
              location.blockIndex < messages[location.messageIndex].blocks.count else { return }
        if case .toolUse(var info) = messages[location.messageIndex].blocks[location.blockIndex] {
            info.elapsedSeconds = progress.elapsedSeconds
            messages[location.messageIndex].blocks[location.blockIndex] = .toolUse(info)
        }
    }

    // MARK: - Helpers

    private func waitForBridgeResponse(_ command: String) async -> BridgeResponse? {
        await withCheckedContinuation { continuation in
            responseContinuations[command] = continuation
        }
    }

    // MARK: - Message Mutation Helpers

    private var currentAssistantIndex: Int {
        if let idx = messages.indices.reversed().first(where: { messages[$0].role == .assistant }) {
            return idx
        }
        messages.append(ChatMessage(role: .assistant))
        return messages.count - 1
    }

    private func updateTextBlock(at messageIndex: Int, text: String) {
        guard messageIndex < messages.count else { return }
        if let textIdx = messages[messageIndex].blocks.lastIndex(where: {
            if case .text = $0 { return true }; return false
        }) {
            if case .text(var info) = messages[messageIndex].blocks[textIdx] {
                info.content = text
                messages[messageIndex].blocks[textIdx] = .text(info)
            }
        } else {
            messages[messageIndex].blocks.append(.text(TextInfo(content: text)))
        }
    }

    private func appendToolUseBlock(at messageIndex: Int, info: ToolUseInfo) -> Int {
        guard messageIndex < messages.count else { return 0 }
        let idx = messages[messageIndex].blocks.count
        messages[messageIndex].blocks.append(.toolUse(info))
        return idx
    }

    private func appendThinkingBlock(at messageIndex: Int, text: String) {
        guard messageIndex < messages.count, !text.isEmpty else { return }
        messages[messageIndex].blocks.append(.thinking(ThinkingInfo(text: text)))
    }

    private func updateThinkingBlock(at messageIndex: Int, text: String) {
        guard messageIndex < messages.count else { return }
        if let idx = messages[messageIndex].blocks.lastIndex(where: {
            if case .thinking = $0 { return true }; return false
        }) {
            if case .thinking(var info) = messages[messageIndex].blocks[idx] {
                info.text = text
                messages[messageIndex].blocks[idx] = .thinking(info)
            }
        } else if !state.hasAddedThinking {
            messages[messageIndex].blocks.append(.thinking(ThinkingInfo(text: text)))
            state.hasAddedThinking = true
        }
    }

    private func updateToolUseInput(at location: BlockLocation, input: [String: Any]) {
        guard location.messageIndex < messages.count,
              location.blockIndex < messages[location.messageIndex].blocks.count else { return }
        if case .toolUse(var info) = messages[location.messageIndex].blocks[location.blockIndex] {
            info.input = input
            messages[location.messageIndex].blocks[location.blockIndex] = .toolUse(info)
        }
    }

    private func attachToolResult(toolID: String, result: ToolResultInfo) {
        guard let location = toolUseIndex[toolID],
              location.messageIndex < messages.count,
              location.blockIndex < messages[location.messageIndex].blocks.count else { return }
        if case .toolUse(var info) = messages[location.messageIndex].blocks[location.blockIndex] {
            info.result = result
            info.isComplete = true
            messages[location.messageIndex].blocks[location.blockIndex] = .toolUse(info)
        }
    }

    private func appendError(_ text: String) {
        error = text
        if let lastIdx = messages.indices.last, messages[lastIdx].role == .assistant {
            messages[lastIdx].blocks = [.text(TextInfo(content: text))]
        }
    }

    private func parseToolInput(_ jsonString: String) -> [String: Any] {
        guard let data = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }

    /// Sync SDK session ID back to the persisted ClaudeSession model.
    private func syncSessionID(_ id: String?) {
        guard let id, claudeSession?.sdkSessionID != id else { return }
        claudeSession?.sdkSessionID = id
    }

    private func formatDict(_ dict: [String: Any]) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.fragmentsAllowed]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return String(describing: dict)
    }
}

// MARK: - Supporting Types

private struct BlockLocation {
    let messageIndex: Int
    let blockIndex: Int
}

private struct StreamState {
    var lastMessageID: String?
    var hasAddedThinking = false
    var thinkingBlockIndices: Set<Int> = []
    var hasStreamedText: Bool { !blockTexts.values.filter({ !$0.isEmpty }).isEmpty }

    var blockTexts: [Int: String] = [:]
    var blockToolIDs: [Int: String] = [:]
    var toolInputJSON: [Int: String] = [:]

    mutating func reset() {
        lastMessageID = nil
        resetBlocks()
    }

    mutating func resetBlocks() {
        hasAddedThinking = false
        thinkingBlockIndices.removeAll()
        blockTexts.removeAll()
        blockToolIDs.removeAll()
        toolInputJSON.removeAll()
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
