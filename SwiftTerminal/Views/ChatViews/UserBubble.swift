import SwiftUI
import AppKit

struct UserMessageView: View {
    let message: Message

    private var chat: Chat { message.chat! }

    private var imageBlocks: [MessageBlock] {
        message.blocks.filter(\.isImage)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if !imageBlocks.isEmpty {
                UserImageStrip(blocks: imageBlocks)
            }

            if !message.text.isEmpty {
                ExpandableText(text: message.text)
                    .padding(12)
                    .background(.background.secondary)
                    .clipShape(.rect(cornerRadius: 20))
            }
        }
        .contentShape(.rect)
        .transaction { $0.animation = nil }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .contextMenu {
            if !message.text.isEmpty {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message.text, forType: .string)
                } label: {
                    Label("Copy Message", systemImage: "doc.on.doc")
                }
            }

            revertButton
        }
        .padding(.leading, 160)
    }

    @ViewBuilder
    private var revertButton: some View {
        let turn = message.turnIndex
        if turn >= 1 && chat.turnCount >= turn {
            Button {
                Task { await chat.revert(toBeforeTurn: turn) }
            } label: {
                Label("Revert to this message", systemImage: "arrow.uturn.backward")
            }
        }
    }
}

private struct UserImageStrip: View {
    let blocks: [MessageBlock]

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(blocks) { block in
                if let data = block.imageData, let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 140, height: 140)
                        .clipShape(.rect(cornerRadius: 14))
                }
            }
        }
    }
}
