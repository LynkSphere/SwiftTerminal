import Foundation

// MARK: - Session Info

@Observable
final class SessionInfo {
    var sessionID: String?
    var model: String?
    var tools: [String] = []
    var totalCost: Double = 0
    var turnCount: Int = 0
    var isInitialized = false
    var permissionMode: PermissionModeOption = .default
    var state: SessionState = .idle
    var isCompacting = false
    var rateLimitStatus: String?
    var claudeCodeVersion: String?

    func update(from system: SystemEvent) {
        sessionID = system.sessionID ?? sessionID
        model = system.model ?? model
        tools = system.tools ?? tools
        isInitialized = true
        if let pm = system.permissionMode, let mode = PermissionModeOption(rawValue: pm) {
            permissionMode = mode
        }
    }

    func update(from result: ResultEvent) {
        sessionID = result.sessionID ?? sessionID
        if let cost = result.totalCostUsd { totalCost = cost }
        if let turns = result.numTurns { turnCount = turns }
    }
}

// MARK: - Permission Mode

enum PermissionModeOption: String, CaseIterable {
    case `default`
    case acceptEdits
    case plan
    case bypassPermissions

    var label: String {
        switch self {
        case .default: "Default"
        case .acceptEdits: "Accept Edits"
        case .plan: "Plan Only"
        case .bypassPermissions: "Full Auto"
        }
    }

    var description: String {
        switch self {
        case .default: "Prompts for dangerous operations"
        case .acceptEdits: "Auto-accept file edits"
        case .plan: "Planning mode, no tool execution"
        case .bypassPermissions: "Bypass all permission checks"
        }
    }
}

// MARK: - Model Option

enum ModelOption: String, CaseIterable {
    case opus = "claude-opus-4-6"
    case sonnet = "claude-sonnet-4-6"
    case haiku = "claude-haiku-4-5-20251001"

    var label: String {
        switch self {
        case .opus: "Opus 4.6"
        case .sonnet: "Sonnet 4.6"
        case .haiku: "Haiku 4.5"
        }
    }

    static func from(modelString: String?) -> ModelOption? {
        guard let model = modelString else { return nil }
        if model.contains("opus") { return .opus }
        if model.contains("sonnet") { return .sonnet }
        if model.contains("haiku") { return .haiku }
        return nil
    }
}

// MARK: - Context Window

enum ContextWindow: String, CaseIterable {
    case standard = "200k"
    case extended = "1m"

    var label: String {
        switch self {
        case .standard: "200K"
        case .extended: "1M"
        }
    }
}

// MARK: - Effort Level

enum EffortLevel: String, CaseIterable {
    case low, medium, high, max

    var label: String { rawValue.capitalized }
}

// MARK: - Session Summary

struct SessionSummary: Identifiable {
    let id: String
    let title: String?
    let lastActive: String?
    let messageCount: Int
}

// MARK: - Rewind Result

struct RewindResult {
    let canRewind: Bool
    let error: String?
    let filesChanged: [String]?
    let insertions: Int?
    let deletions: Int?
}
