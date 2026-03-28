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
                result: raw["result"] as? [String: Any]
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

        // Elicitation request from MCP server
        case "elicitation_request":
            return parseElicitationRequest(raw)

        // SDK messages (unwrap the wrapper)
        case "sdk_message":
            guard let message = raw["message"] as? [String: Any],
                  let msgType = message["type"] as? String else { return nil }
            return parseSDKMessage(msgType, message)

        // Direct SDK event types (for backwards compatibility)
        case "system", "assistant", "user", "result", "rate_limit_event", "stream_event",
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
            guard let data = try? JSONSerialization.data(withJSONObject: raw),
                  let event = try? JSONDecoder().decode(UserEvent.self, from: data) else { return nil }
            return .user(event)

        case "result":
            guard let data = try? JSONSerialization.data(withJSONObject: raw),
                  let event = try? JSONDecoder().decode(ResultEvent.self, from: data) else { return nil }
            return .result(event)

        case "rate_limit_event":
            guard let data = try? JSONSerialization.data(withJSONObject: raw),
                  let event = try? JSONDecoder().decode(RateLimitEvent.self, from: data) else { return nil }
            return .rateLimit(event)

        case "stream_event":
            return parseStreamEvent(raw)

        case "tool_progress":
            return parseToolProgress(raw)

        case "task_started", "task_progress", "task_notification":
            return parseTaskEvent(type, raw)

        case "prompt_suggestion":
            return parsePromptSuggestion(raw)

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
            return parseTaskEvent("task_notification", raw)

        case "task_started":
            return parseTaskEvent("task_started", raw)

        case "task_progress":
            return parseTaskEvent("task_progress", raw)

        default:
            guard let data = try? JSONSerialization.data(withJSONObject: raw),
                  let event = try? JSONDecoder().decode(SystemEvent.self, from: data) else { return nil }
            return .system(event)
        }
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

    // MARK: - Elicitation Request

    private static func parseElicitationRequest(_ raw: [String: Any]) -> StreamEvent? {
        guard let requestId = raw["requestId"] as? String,
              let serverName = raw["serverName"] as? String,
              let message = raw["message"] as? String else { return nil }

        let modeStr = raw["mode"] as? String ?? "form"
        let mode = ElicitationMode(rawValue: modeStr) ?? .form

        let request = ElicitationRequest(
            requestId: requestId,
            serverName: serverName,
            message: message,
            mode: mode,
            url: raw["url"] as? String,
            requestedSchema: raw["requestedSchema"] as? [String: Any]
        )
        return .elicitationRequest(request)
    }

    // MARK: - Prompt Suggestion

    private static func parsePromptSuggestion(_ raw: [String: Any]) -> StreamEvent? {
        guard let suggestions = raw["suggestions"] as? [String] else { return nil }
        return .promptSuggestion(PromptSuggestionEvent(suggestions: suggestions))
    }

    // MARK: - Task Events

    private static func parseTaskEvent(_ type: String, _ raw: [String: Any]) -> StreamEvent? {
        let taskID = raw["task_id"] as? String ?? ""
        let toolUseID = raw["tool_use_id"] as? String
        let summary = raw["summary"] as? String
        let outputFile = raw["output_file"] as? String

        let status: TaskStatus
        switch type {
        case "task_started":
            status = .started
        case "task_progress":
            status = .inProgress
        case "task_notification":
            let rawStatus = raw["status"] as? String ?? "completed"
            status = TaskStatus(rawValue: rawStatus) ?? .completed
        default:
            status = .started
        }

        let event = TaskEvent(
            id: taskID,
            taskID: taskID,
            toolUseID: toolUseID,
            status: status,
            summary: summary,
            outputFile: outputFile
        )

        switch type {
        case "task_started":
            return .taskStarted(event)
        case "task_progress":
            return .taskProgress(event)
        case "task_notification":
            return .taskCompleted(event)
        default:
            return .taskStarted(event)
        }
    }
}
