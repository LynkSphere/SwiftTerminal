import Foundation

// MARK: - Top-Level Stream Events

/// Discriminated union for all JSON lines from the Claude Agent SDK bridge.
enum StreamEvent {
    case system(SystemEvent)
    case assistant(AssistantEvent)
    case user(UserEvent)
    case result(ResultEvent)
    case rateLimit(RateLimitEvent)
    case streamEvent(StreamDelta)
    case approvalRequest(ApprovalRequest)
    case toolProgress(ToolProgressEvent)
    case sessionStateChanged(SessionStateEvent)
    case statusUpdate(StatusEvent)
    case taskStarted(TaskEvent)
    case taskProgress(TaskEvent)
    case taskCompleted(TaskEvent)
    case elicitationRequest(ElicitationRequest)
    case promptSuggestion(PromptSuggestionEvent)
    case bridgeReady
    case bridgeResponse(BridgeResponse)
    case bridgeError(BridgeError)
    case sdkDone
    case unknown(String)
}

// MARK: - Status Event

struct StatusEvent {
    let status: String? // "compacting" or nil
    let sessionID: String
}

// MARK: - Bridge Protocol

struct BridgeResponse {
    let command: String
    let success: Bool
    let sessions: [[String: Any]]?
    let messages: [[String: Any]]?
    let result: [String: Any]?
}

struct BridgeError {
    let command: String?
    let error: String
}

// MARK: - Approval Request

struct ApprovalRequest: Identifiable {
    let id: String
    let requestId: String
    let toolName: String
    let input: [String: Any]
    let toolUseID: String
    let title: String?
    let displayName: String?
    let description: String?
    let decisionReason: String?

    init(requestId: String, toolName: String, input: [String: Any], toolUseID: String,
         title: String?, displayName: String?, description: String?, decisionReason: String?) {
        self.id = requestId
        self.requestId = requestId
        self.toolName = toolName
        self.input = input
        self.toolUseID = toolUseID
        self.title = title
        self.displayName = displayName
        self.description = description
        self.decisionReason = decisionReason
    }
}

// MARK: - Tool Progress

struct ToolProgressEvent {
    let toolUseID: String
    let toolName: String
    let elapsedSeconds: Double
    let taskID: String?
}

// MARK: - Task Events (Sub-agents)

struct TaskEvent: Identifiable {
    let id: String
    let taskID: String
    let toolUseID: String?
    let status: TaskStatus
    let summary: String?
    let outputFile: String?
}

enum TaskStatus: String {
    case started
    case inProgress = "in_progress"
    case completed
    case failed
    case stopped
}

// MARK: - Session State

struct SessionStateEvent {
    let state: SessionState
    let sessionID: String
}

enum SessionState: String {
    case idle
    case running
    case requiresAction = "requires_action"
}

// MARK: - Stream Delta (from --include-partial-messages)

struct StreamDelta {
    let eventType: String
    let index: Int?
    let delta: DeltaPayload?
    let contentBlock: ContentBlockStart?
    let sessionID: String?
}

struct DeltaPayload {
    let type: String
    let text: String?
    let partialJSON: String?
}

struct ContentBlockStart {
    let type: String
    let text: String?
    let id: String?
    let name: String?
}

// MARK: - System Init

struct SystemEvent: Decodable {
    let subtype: String
    let cwd: String?
    let sessionID: String?
    let model: String?
    let tools: [String]?
    let permissionMode: String?

    enum CodingKeys: String, CodingKey {
        case subtype, cwd, model, tools
        case sessionID = "session_id"
        case permissionMode = "permission_mode"
    }
}

// MARK: - Assistant Message

struct AssistantEvent: Decodable {
    let message: AssistantMessage
    let sessionID: String?

    enum CodingKeys: String, CodingKey {
        case message
        case sessionID = "session_id"
    }
}

struct AssistantMessage: Decodable {
    let id: String?
    let role: String
    let content: [ContentBlock]
    let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case id, role, content
        case stopReason = "stop_reason"
    }
}

// MARK: - Content Blocks

enum ContentBlock: Decodable {
    case text(TextBlock)
    case toolUse(ToolUseBlock)
    case thinking(ThinkingBlock)
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            self = .text(try TextBlock(from: decoder))
        case "tool_use":
            self = .toolUse(try ToolUseBlock(from: decoder))
        case "thinking":
            self = .thinking(try ThinkingBlock(from: decoder))
        default:
            self = .unknown
        }
    }

    private enum TypeKey: String, CodingKey {
        case type
    }
}

struct TextBlock: Decodable {
    let text: String
}

struct ToolUseBlock: Decodable {
    let id: String
    let name: String
    let input: [String: AnyCodable]
}

struct ThinkingBlock: Decodable {
    let thinking: String
}

// MARK: - User Message (Tool Results)

struct UserEvent: Decodable {
    let message: UserMessage
    let sessionID: String?
    let toolUseResult: ToolUseResult?

    enum CodingKeys: String, CodingKey {
        case message
        case sessionID = "session_id"
        case toolUseResult = "tool_use_result"
    }
}

struct UserMessage: Decodable {
    let role: String
    let content: [ToolResultContent]
}

struct ToolResultContent: Decodable {
    let toolUseID: String?
    let type: String
    let content: AnyCodable?

    enum CodingKeys: String, CodingKey {
        case toolUseID = "tool_use_id"
        case type, content
    }
}

struct ToolUseResult: Decodable {
    let type: String?
    let file: ToolResultFile?
}

struct ToolResultFile: Decodable {
    let filePath: String?
    let numLines: Int?
}

// MARK: - Result

struct ResultEvent: Decodable {
    let subtype: String?
    let isError: Bool?
    let result: String?
    let sessionID: String?
    let durationMs: Int?
    let numTurns: Int?
    let totalCostUsd: Double?

    enum CodingKeys: String, CodingKey {
        case subtype, result
        case isError = "is_error"
        case sessionID = "session_id"
        case durationMs = "duration_ms"
        case numTurns = "num_turns"
        case totalCostUsd = "total_cost_usd"
    }
}

// MARK: - Rate Limit

struct RateLimitEvent: Decodable {
    let rateLimitInfo: RateLimitInfo?

    enum CodingKeys: String, CodingKey {
        case rateLimitInfo = "rate_limit_info"
    }
}

struct RateLimitInfo: Decodable {
    let status: String?
}

// MARK: - Elicitation Request (MCP Server Input)

struct ElicitationRequest: Identifiable {
    var id: String { requestId }
    let requestId: String
    let serverName: String
    let message: String
    let mode: ElicitationMode
    let url: String?
    let requestedSchema: [String: Any]?
}

enum ElicitationMode: String {
    case form
    case url
}

// MARK: - Prompt Suggestion

struct PromptSuggestionEvent {
    let suggestions: [String]
}

// MARK: - AnyCodable Helper

struct AnyCodable: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else {
            value = NSNull()
        }
    }

    var stringValue: String? { value as? String }
    var dictValue: [String: Any]? { value as? [String: Any] }
}
