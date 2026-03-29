import Foundation

/// Parses JSON lines from the Claude bridge into typed StreamEvents.
enum StreamParser {

    static func parse(_ line: String) -> StreamEvent? {
        guard let data = line.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = raw["type"] as? String else {
            return nil
        }

        switch type {
        // Bridge protocol messages
        case "bridge_ready":
            return .bridgeReady

        case "bridge_response":
            let resp = BridgeResponse(
                command: raw["command"] as? String ?? "",
                success: raw["success"] as? Bool ?? false,
                sessions: raw["sessions"] as? [[String: Any]],
                messages: raw["messages"] as? [[String: Any]],
                result: raw["result"] as? [String: Any],
                userMessageUUID: raw["userMessageUUID"] as? String
            )
            return .bridgeResponse(resp)

        case "bridge_error":
            let err = BridgeError(
                command: raw["command"] as? String,
                error: raw["error"] as? String ?? "Unknown error"
            )
            return .bridgeError(err)

        case "sdk_done":
            return .sdkDone

        case "sdk_error":
            let errMsg = raw["error"] as? String ?? "Unknown SDK error"
            return .bridgeError(BridgeError(command: nil, error: errMsg))

        // Approval request from bridge permission handler
        case "approval_request":
            return parseApprovalRequest(raw)

        // Plan review request (ExitPlanMode tool intercepted in bridge)
        case "plan_review_request":
            return parsePlanReviewRequest(raw)

        // Question request (AskUserQuestion tool intercepted in bridge)
        case "question_request":
            return parseQuestionRequest(raw)

        // SDK messages (unwrap the wrapper)
        case "sdk_message":
            guard let message = raw["message"] as? [String: Any],
                  let msgType = message["type"] as? String else { return nil }
            return parseSDKMessage(msgType, message)

        // Direct SDK event types (for backwards compatibility)
        case "system", "assistant", "user", "result", "stream_event",
             "tool_progress", "tool_use_summary":
            return parseSDKMessage(type, raw)

        default:
            return .unknown(type)
        }
    }

    // MARK: - Approval Request

    private static func parseApprovalRequest(_ raw: [String: Any]) -> StreamEvent? {
        guard let requestId = raw["requestId"] as? String,
              let toolName = raw["toolName"] as? String else { return nil }

        let request = ApprovalRequest(
            requestId: requestId,
            toolName: toolName,
            input: raw["input"] as? [String: Any] ?? [:],
            toolUseID: raw["toolUseID"] as? String ?? requestId,
            title: raw["title"] as? String,
            displayName: raw["displayName"] as? String,
            description: raw["description"] as? String,
            decisionReason: raw["decisionReason"] as? String
        )
        return .approvalRequest(request)
    }

    // MARK: - Plan Review Request

    private static func parsePlanReviewRequest(_ raw: [String: Any]) -> StreamEvent? {
        guard let requestId = raw["requestId"] as? String else { return nil }

        let request = ApprovalRequest(
            requestId: requestId,
            toolName: "ExitPlanMode",
            input: raw["input"] as? [String: Any] ?? [:],
            toolUseID: raw["toolUseID"] as? String ?? requestId,
            title: nil,
            displayName: nil,
            description: nil,
            decisionReason: nil
        )
        return .planReviewRequest(request)
    }

    // MARK: - Question Request

    private static func parseQuestionRequest(_ raw: [String: Any]) -> StreamEvent? {
        guard let requestId = raw["requestId"] as? String else { return nil }

        var items: [QuestionItem] = []
        if let rawQuestions = raw["questions"] as? [[String: Any]] {
            for q in rawQuestions {
                let question = q["question"] as? String ?? ""
                let header = q["header"] as? String ?? ""
                let multiSelect = q["multiSelect"] as? Bool ?? false

                var options: [QuestionOption] = []
                if let rawOptions = q["options"] as? [[String: Any]] {
                    for opt in rawOptions {
                        options.append(QuestionOption(
                            label: opt["label"] as? String ?? "",
                            description: opt["description"] as? String ?? ""
                        ))
                    }
                }

                items.append(QuestionItem(
                    question: question,
                    header: header,
                    options: options,
                    multiSelect: multiSelect
                ))
            }
        }

        let request = QuestionRequest(
            requestId: requestId,
            toolUseID: raw["toolUseID"] as? String ?? requestId,
            questions: items
        )
        return .questionRequest(request)
    }

    // MARK: - SDK Message Parsing

    private static func parseSDKMessage(_ type: String, _ raw: [String: Any]) -> StreamEvent? {
        switch type {
        case "system":
            return parseSystemMessage(raw)

        case "assistant":
            guard let data = try? JSONSerialization.data(withJSONObject: raw),
                  let event = try? JSONDecoder().decode(AssistantEvent.self, from: data) else { return nil }
            return .assistant(event)

        case "user":
            return parseUserMessage(raw)

        case "result":
            guard let data = try? JSONSerialization.data(withJSONObject: raw),
                  let event = try? JSONDecoder().decode(ResultEvent.self, from: data) else { return nil }
            return .result(event)

        case "stream_event":
            return parseStreamEvent(raw)

        case "tool_progress":
            return parseToolProgress(raw)

        case "task_started", "task_progress", "task_notification":
            return parseTaskEvent(type)

        default:
            return .unknown(type)
        }
    }

    // MARK: - System Messages

    private static func parseSystemMessage(_ raw: [String: Any]) -> StreamEvent? {
        guard let subtype = raw["subtype"] as? String else { return nil }

        switch subtype {
        case "session_state_changed":
            let stateStr = raw["state"] as? String ?? "idle"
            let state = SessionState(rawValue: stateStr) ?? .idle
            let sessionID = raw["session_id"] as? String ?? ""
            return .sessionStateChanged(SessionStateEvent(state: state, sessionID: sessionID))

        case "status":
            let status = raw["status"] as? String
            let sessionID = raw["session_id"] as? String ?? ""
            return .statusUpdate(StatusEvent(status: status, sessionID: sessionID))

        case "task_notification":
            return .taskCompleted

        case "task_started":
            return .taskStarted

        case "task_progress":
            return .taskProgress

        default:
            guard let data = try? JSONSerialization.data(withJSONObject: raw),
                  let event = try? JSONDecoder().decode(SystemEvent.self, from: data) else { return nil }
            return .system(event)
        }
    }

    // MARK: - User Messages

    /// Manual JSON parsing for user events — avoids JSONDecoder which silently
    /// drops the entire event when any tool result has an unexpected content
    /// format (array vs string vs dict). This ensures isComplete is set for
    /// every tool result, preventing stuck spinners.
    private static func parseUserMessage(_ raw: [String: Any]) -> StreamEvent? {
        guard let message = raw["message"] as? [String: Any],
              let contentArray = message["content"] as? [[String: Any]] else { return nil }

        let sessionID = raw["session_id"] as? String

        var resultContents: [ToolResultContent] = []
        for block in contentArray {
            let type = block["type"] as? String ?? ""
            let toolUseID = block["tool_use_id"] as? String

            // Robustly extract content regardless of format (string, array, dict, null)
            let content: AnyCodable?
            if let str = block["content"] as? String {
                content = AnyCodable(stringLiteral: str)
            } else if let obj = block["content"], JSONSerialization.isValidJSONObject(obj),
                      let data = try? JSONSerialization.data(withJSONObject: obj),
                      let decoded = try? JSONDecoder().decode(AnyCodable.self, from: data) {
                content = decoded
            } else {
                content = nil
            }

            resultContents.append(ToolResultContent(
                toolUseID: toolUseID,
                type: type,
                content: content
            ))
        }

        // Parse top-level tool_use_result metadata if present
        var toolUseResult: ToolUseResult?
        if let tur = raw["tool_use_result"] as? [String: Any] {
            var file: ToolResultFile?
            if let f = tur["file"] as? [String: Any] {
                file = ToolResultFile(
                    filePath: f["filePath"] as? String ?? f["file_path"] as? String,
                    numLines: f["numLines"] as? Int ?? f["num_lines"] as? Int
                )
            }
            toolUseResult = ToolUseResult(type: tur["type"] as? String, file: file)
        }

        let event = UserEvent(
            message: UserMessage(role: "user", content: resultContents),
            sessionID: sessionID,
            toolUseResult: toolUseResult
        )
        return .user(event)
    }

    // MARK: - Stream Events

    private static func parseStreamEvent(_ raw: [String: Any]) -> StreamEvent? {
        guard let event = raw["event"] as? [String: Any],
              let eventType = event["type"] as? String else { return nil }

        let sessionID = raw["session_id"] as? String
        let index = event["index"] as? Int

        var delta: DeltaPayload?
        if let d = event["delta"] as? [String: Any] {
            delta = DeltaPayload(
                type: d["type"] as? String ?? "",
                text: d["text"] as? String,
                partialJSON: d["partial_json"] as? String
            )
        }

        var contentBlock: ContentBlockStart?
        if let cb = event["content_block"] as? [String: Any] {
            contentBlock = ContentBlockStart(
                type: cb["type"] as? String ?? "",
                text: cb["text"] as? String,
                id: cb["id"] as? String,
                name: cb["name"] as? String
            )
        }

        return .streamEvent(StreamDelta(
            eventType: eventType,
            index: index,
            delta: delta,
            contentBlock: contentBlock,
            sessionID: sessionID
        ))
    }

    // MARK: - Tool Progress

    private static func parseToolProgress(_ raw: [String: Any]) -> StreamEvent? {
        guard let toolUseID = raw["tool_use_id"] as? String,
              let toolName = raw["tool_name"] as? String else { return nil }

        let elapsed = raw["elapsed_time_seconds"] as? Double ?? 0

        return .toolProgress(ToolProgressEvent(
            toolUseID: toolUseID,
            toolName: toolName,
            elapsedSeconds: elapsed,
            taskID: raw["task_id"] as? String
        ))
    }

    // MARK: - Task Events

    private static func parseTaskEvent(_ type: String) -> StreamEvent {
        switch type {
        case "task_started": .taskStarted
        case "task_progress": .taskProgress
        default: .taskCompleted
        }
    }
}
