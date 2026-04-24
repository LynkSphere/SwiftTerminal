import Foundation

// Permission mode for ACP agents.
enum PermissionMode: String, Codable, CaseIterable, Identifiable {
    /// Standard behavior — prompts for dangerous operations.
    /// Claude: "default", Codex: "auto"
    case standard

    /// Auto-accept file edit operations (Claude only).
    /// Claude: "acceptEdits", Codex: falls back to "auto"
    case acceptEdits

    /// Bypass all permission checks.
    /// Claude: "bypassPermissions", Codex: "full-access"
    case bypassPermissions

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: return "Default"
        case .acceptEdits: return "Accept Edits"
        case .bypassPermissions: return "Bypass Permissions"
        }
    }

    var description: String {
        switch self {
        case .standard: return "Prompts for dangerous operations"
        case .acceptEdits: return "Auto-accept file edits"
        case .bypassPermissions: return "Skip all permission checks"
        }
    }

    /// The config value string to send to the Claude ACP agent.
    var claudeConfigValue: String {
        switch self {
        case .standard: return "default"
        case .acceptEdits: return "acceptEdits"
        case .bypassPermissions: return "bypassPermissions"
        }
    }

    /// The config value string to send to the Codex ACP agent.
    var codexConfigValue: String {
        switch self {
        case .standard: return "auto"
        case .acceptEdits: return "auto"
        case .bypassPermissions: return "full-access"
        }
    }

    func configValue(for provider: AgentProvider) -> String {
        switch provider {
        case .claude: return claudeConfigValue
        case .codex: return codexConfigValue
        }
    }
}
