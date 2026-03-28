import SwiftUI

struct MessageView: View {
    let message: ChatMessage
    let isStreaming: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .assistant {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.purple)
                    .frame(width: 20, height: 20)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(message.role == .user ? "You" : "Claude")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)

                if message.blocks.isEmpty && isStreaming {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(height: 16)
                } else {
                    ForEach(message.blocks) { block in
                        blockView(block)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if message.role == .user {
                Image(systemName: "person.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }
        }
        .padding(.horizontal, message.role == .user ? 40 : 0)
    }

    @ViewBuilder
    private func blockView(_ block: MessageBlock) -> some View {
        switch block {
        case .text(let info):
            MarkdownTextView(text: info.content)

        case .toolUse(let info):
            ToolUseView(info: info)

        case .toolResult:
            EmptyView()

        case .thinking(let info):
            ThinkingView(info: info)
        }
    }
}
