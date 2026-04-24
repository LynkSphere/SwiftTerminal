import Foundation

enum AgentModel: String, Codable, CaseIterable, Identifiable {
    // Claude
    case claudeHaiku = "claude-haiku-4-5"
    case claudeSonnet = "claude-sonnet-4-6"
    case claudeOpus = "claude-opus-4-6"

    // Codex
    case gpt54 = "gpt-5.4"
    case gpt54Mini = "gpt-5-mini"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .claudeHaiku: return "Haiku"
        case .claudeSonnet: return "Sonnet"
        case .claudeOpus: return "Opus"
        case .gpt54: return "GPT-5.4"
        case .gpt54Mini: return "GPT-5 Mini"
        }
    }

    var imageName: String {
        switch self {
        case .claudeHaiku, .claudeSonnet, .claudeOpus:
            return "claude.symbols"
        case .gpt54, .gpt54Mini:
            return "openai.symbols"
        }
    }

    var provider: AgentProvider {
        switch self {
        case .claudeHaiku, .claudeSonnet, .claudeOpus: return .claude
        case .gpt54, .gpt54Mini: return .codex
        }
    }

    static func models(for provider: AgentProvider) -> [AgentModel] {
        allCases.filter { $0.provider == provider }
    }

    static func defaultModel(for provider: AgentProvider) -> AgentModel {
        switch provider {
        case .claude: return .claudeSonnet
        case .codex: return .gpt54
        }
    }
}
