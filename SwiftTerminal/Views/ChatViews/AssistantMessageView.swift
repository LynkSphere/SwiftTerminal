import SwiftUI
import ACP

struct AssistantMessageView: View {
    @AppStorage("fontSize") private var fontSize: Double = 13
    @Environment(EditorPanel.self) private var editorPanel

    let message: Message

    @State private var measuredHeight: CGFloat = 0

    private var chat: Chat { message.chat! }
    private var session: ACPSession { chat.session }
    private var isLastMessage: Bool { message.id == chat.messages.last?.id }

    private func resolveFileURL(_ path: String) -> URL? {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        guard let workspaceURL = chat.workspace?.url else { return nil }
        return workspaceURL.appendingPathComponent(path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AssistantLabel(provider: chat.provider)

            VStack(alignment: .leading, spacing: 8) {
                AssistantBlocksRepresentable(
                    blocks: message.blocks,
                    fontSize: fontSize,
                    cachedHeight: message.height,
                    calculatedHeight: $measuredHeight,
                    onOpenFile: { path in
                        guard let url = resolveFileURL(path) else { return }
                        editorPanel.openFile(url)
                    }
                )
                .frame(height: message.height > 0 ? message.height : nil, alignment: .top)
                .onChange(of: measuredHeight) { _, newHeight in
                    guard newHeight > 0, message.height != newHeight else { return }
                    message.height = newHeight
                }
                .transaction { $0.animation = nil }

                if session.isProcessing && isLastMessage {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.leading, 25)
        }
        .contentShape(.rect)
        .transaction { $0.animation = nil }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 30)
    }
}
