import Foundation

enum AgentThreadStatus: String, Codable, Sendable {
    case processing = "Processing"
    case waiting = "Needs input"
    case done = "Done"
    case idle = "Ready"
    case failed = "Failed"
    case stopped = "Stopped"
    case unknown = "Offline"

    static func codex(_ status: [String: Any]?) -> Self {
        switch status?["type"] as? String {
        case "active":
            let flags = status?["activeFlags"] as? [String] ?? []
            return flags.contains("waitingOnApproval") || flags.contains("waitingOnUserInput") ? .waiting : .processing
        case "idle": return .idle
        case "systemError": return .failed
        default: return .unknown
        }
    }

}
