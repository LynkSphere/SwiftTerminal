import SwiftUI

struct MessageListView: View {
    let service: ClaudeService

    var body: some View {
        ForEach(turns) { turn in
            switch turn.kind {
            case .user(let message):
                UserMessageView(message: message, service: service)
                    .id(turn.id)
                    .listRowSeparator(.hidden)

            case .assistant(let messages):
                AssistantTurnView(
                    messages: messages,
                    isStreaming: service.isStreaming && turn.isLast
                )
                .id(turn.id)
                .listRowSeparator(.hidden)
            }
        }
    }

    /// Groups all consecutive assistant messages between user messages into a single turn.
    private var turns: [Turn] {
        var result: [Turn] = []
        let lastID = service.messages.last?.id

        for message in service.messages {
            switch message.role {
            case .user:
                result.append(Turn(
                    kind: .user(message),
                    isLast: message.id == lastID
                ))

            case .assistant:
                if case .assistant(let existing) = result.last?.kind {
                    var msgs = existing
                    msgs.append(message)
                    result[result.count - 1] = Turn(
                        kind: .assistant(msgs),
                        isLast: message.id == lastID
                    )
                } else {
                    result.append(Turn(
                        kind: .assistant([message]),
                        isLast: message.id == lastID
                    ))
                }

            case .system:
                break
            }
        }
        return result
    }
}

// MARK: - Turn

struct Turn: Identifiable {
    let kind: Kind
    var isLast: Bool

    enum Kind {
        case user(ChatMessage)
        case assistant([ChatMessage])
    }

    var id: String {
        switch kind {
        case .user(let m): m.id
        case .assistant(let ms): ms.first?.id ?? UUID().uuidString
        }
    }
}

// MARK: - User Message

struct UserMessageView: View {
    let message: ChatMessage
    let service: ClaudeService

    var body: some View {
        VStack(alignment: .trailing) {
            Text(message.text)
                .padding(12)
                .background(.background.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .contextMenu {
                    Button("Copy", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.text, forType: .string)
                    }
                    Divider()
                    Button("Rewind to here", systemImage: "arrow.counterclockwise") {
                        Task {
                            await service.rewind(toMessageID: message.id)
                        }
                    }
                    .disabled(service.isStreaming)
                }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 160)
    }
}

// MARK: - Assistant Turn (single Claude label for all consecutive messages)

struct AssistantTurnView: View {
    let messages: [ChatMessage]
    let isStreaming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ClaudeLabel()

            VStack(alignment: .leading, spacing: 8) {
                ForEach(groupedContent) { group in
                    switch group {
                    case .text(let info):
                        MacMarkdownRepresentable(
                            text: info.content,
                            fontSize: 13,
                            isStreaming: isStreaming
                        )

                    case .toolGroup(let tools):
                        ToolGroupView(tools: tools)

                    case .editDiff(let tool):
//                    TODO: define
                        Text(tool.result?.content ?? "")
//                        InlineEditDiffView(tool: tool)
                    }
                }

                if isStreaming && allBlocks.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.leading, 25)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 5)
        .padding(.trailing, 30)
    }

    private var allBlocks: [MessageBlock] {
        messages.flatMap(\.blocks)
    }

    private var groupedContent: [ContentGroup] {
        var groups: [ContentGroup] = []
        var pendingTools: [ToolUseInfo] = []

        func flushPendingTools() {
            guard !pendingTools.isEmpty else { return }
            groups.append(.toolGroup(pendingTools))
            pendingTools = []
        }

        for block in allBlocks {
            switch block {
            case .text(let info):
                flushPendingTools()
                if !info.content.isEmpty {
                    groups.append(.text(info))
                }

            case .toolUse(let info):
                if info.name == "Edit" || info.name == "Write" {
                    flushPendingTools()
                    groups.append(.editDiff(info))
                } else {
                    pendingTools.append(info)
                }

            case .thinking, .toolResult:
                break
            }
        }

        flushPendingTools()
        return groups
    }
}

// MARK: - Content Grouping

private enum ContentGroup: Identifiable {
    case text(TextInfo)
    case toolGroup([ToolUseInfo])
    case editDiff(ToolUseInfo)

    var id: String {
        switch self {
        case .text(let info): "text-\(info.id)"
        case .toolGroup(let tools): "tools-\(tools.map(\.id).joined(separator: "-"))"
        case .editDiff(let tool): "edit-\(tool.id)"
        }
    }
}
