import Foundation

struct ClaudeHookEvent: Decodable, Sendable {
    let sessionID: String
    let name: String
    let directory: String?
    let agentID: String?
    let toolName: String?
    let notificationType: String?
    let sessionTitle: String?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case name = "hook_event_name"
        case directory = "cwd"
        case agentID = "agent_id"
        case toolName = "tool_name"
        case notificationType = "notification_type"
        case sessionTitle = "session_title"
    }

    var status: AgentThreadStatus? {
        guard agentID == nil else { return nil }
        switch name {
        case "SessionStart": return .idle
        case "UserPromptSubmit", "PostToolUse", "PostToolUseFailure", "ElicitationResult": return .processing
        case "PreToolUse": return toolName == "AskUserQuestion" ? .waiting : .processing
        case "PermissionRequest", "Elicitation": return .waiting
        case "Notification":
            guard let notificationType else { return nil }
            return ["permission_prompt", "elicitation_dialog", "elicitation_url_dialog"].contains(notificationType) ? .waiting : nil
        case "Stop": return .done
        case "StopFailure": return .failed
        case "SessionEnd": return .stopped
        default: return nil
        }
    }
}
