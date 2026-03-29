import Foundation

// MARK: - Chat Message

struct ChatMessage: Identifiable {
    let id: String
    let role: MessageRole
    var blocks: [MessageBlock]
    let timestamp: Date

    init(role: MessageRole, blocks: [MessageBlock] = []) {
        self.id = UUID().uuidString
        self.role = role
        self.blocks = blocks
        self.timestamp = Date()
    }

    var text: String {
        blocks.compactMap { block in
            if case .text(let info) = block { return info.content }
            return nil
        }.joined()
    }

    var hasToolUse: Bool {
        blocks.contains { block in
            if case .toolUse = block { return true }
            return false
        }
    }
}

// MARK: - Message Role

enum MessageRole {
    case user
    case assistant
    case system
}

// MARK: - Message Block

enum MessageBlock: Identifiable {
    case text(TextInfo)
    case toolUse(ToolUseInfo)
    case toolResult(ToolResultInfo)
    case thinking(ThinkingInfo)
    case image(ImageInfo)

    var id: String {
        switch self {
        case .text(let info): "text-\(info.id)"
        case .toolUse(let info): "tool-\(info.id)"
        case .toolResult(let info): "result-\(info.toolUseID)"
        case .thinking(let info): "think-\(info.id)"
        case .image(let info): "img-\(info.id)"
        }
    }
}

// MARK: - Text Info

struct TextInfo: Identifiable {
    let id: String
    var content: String

    init(content: String) {
        self.id = UUID().uuidString
        self.content = content
    }
}

// MARK: - Tool Use Info

struct ToolUseInfo: Identifiable {
    let id: String
    let name: String
    var input: [String: Any]
    var result: ToolResultInfo?
    var isComplete = false
    var elapsedSeconds: Double?

    var inputSummary: String {
        switch name {
        case "Read":
            return (input["file_path"] as? String).map { shortenPath($0) } ?? "file"
        case "Write":
            return (input["file_path"] as? String).map { "Writing \(shortenPath($0))" } ?? "file"
        case "Edit":
            return (input["file_path"] as? String).map { "Editing \(shortenPath($0))" } ?? "file"
        case "Bash":
            let cmd = (input["command"] as? String) ?? ""
            let desc = (input["description"] as? String)
            return desc ?? String(cmd.prefix(80))
        case "Glob":
            return (input["pattern"] as? String) ?? "pattern"
        case "Grep":
            return (input["pattern"] as? String).map { "Searching: \($0)" } ?? "search"
        case "Agent":
            return (input["description"] as? String) ?? "sub-agent"
        case "WebFetch":
            return (input["url"] as? String).map { shortenURL($0) } ?? "fetch"
        case "WebSearch":
            return (input["query"] as? String) ?? "search"
        case "NotebookEdit":
            return (input["notebook_path"] as? String).map { shortenPath($0) } ?? "notebook"
        default:
            return name
        }
    }

    var category: ToolCategory {
        switch name {
        case "Read": .file
        case "Write", "Edit", "NotebookEdit": .edit
        case "Bash": .terminal
        case "Glob", "Grep": .search
        case "Agent": .agent
        case "WebFetch", "WebSearch": .web
        case "Skill": .skill
        default: .other
        }
    }
}

enum ToolCategory {
    case file, edit, terminal, search, agent, web, skill, other

    var iconName: String {
        switch self {
        case .file: "doc.text"
        case .edit: "pencil"
        case .terminal: "terminal"
        case .search: "magnifyingglass"
        case .agent: "person.2"
        case .web: "globe"
        case .skill: "bolt.fill"
        case .other: "wrench"
        }
    }
}

// MARK: - Tool Result Info

struct ToolResultInfo {
    let toolUseID: String
    let content: String
    let filePath: String?
    let numLines: Int?
}

// MARK: - Thinking Info

struct ThinkingInfo: Identifiable {
    let id: String
    var text: String

    init(text: String) {
        self.id = UUID().uuidString
        self.text = text
    }
}

// MARK: - Image Info

struct ImageInfo: Identifiable {
    let id: String
    let data: Data
    let mediaType: String

    init(data: Data, mediaType: String) {
        self.id = UUID().uuidString
        self.data = data
        self.mediaType = mediaType
    }
}

// MARK: - Helpers

private func shortenPath(_ path: String) -> String {
    let components = path.split(separator: "/")
    if components.count <= 3 { return path }
    return ".../" + components.suffix(2).joined(separator: "/")
}

private func shortenURL(_ url: String) -> String {
    guard let parsed = URL(string: url) else { return String(url.prefix(50)) }
    return parsed.host ?? String(url.prefix(50))
}
