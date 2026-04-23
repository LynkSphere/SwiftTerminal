import SwiftUI

struct ACPInputArea: View {
    @Bindable var chat: Chat
    @FocusState private var isFocused: Bool

    private var session: ACPSession { chat.session }

    var body: some View {
        GlassEffectContainer {
            HStack(alignment: .bottom) {
                ACPInputMenu()
                    .offset(y: -1)

                ZStack(alignment: .leading) {
                    if chat.prompt.isEmpty {
                        Text("Message \(chat.provider.rawValue)...")
                            .padding(.leading, 1)
                            .foregroundStyle(.placeholder)
                    }

                    TextEditor(text: $chat.prompt)
                        .padding(.leading, -4)
                        .frame(maxHeight: 350)
                        .fixedSize(horizontal: false, vertical: true)
                        .scrollContentBackground(.hidden)
                        .focused($isFocused)
                }
                .font(.body)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .padding(6)
                .glassEffect(in: .rect(cornerRadius: 16))

                Button {
                    session.isProcessing ? session.stopStreaming() : send()
                } label: {
                    Image(systemName: session.isProcessing ? "stop.fill" : "arrow.up")
                        .font(.system(size: 15)).fontWeight(.bold)
                }
                .opacity(0.85)
                .controlSize(.large)
                .tint(session.isProcessing ? .red : .accent)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .disabled(!session.isProcessing && (chat.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.isConnecting))
                .offset(y: -2)
                .keyboardShortcut(session.isProcessing ? "d" : .return, modifiers: [.command])
            }
            .padding(12)
        }
        .task {
            isFocused = true
        }
    }

    private func send() {
        let text = chat.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        chat.prompt = ""
        chat.sendMessage(text)
    }
}

// MARK: - Input Menu

private struct ACPInputMenu: View {
    var body: some View {
        Menu {
            Group {
                Button {
                } label: {
                    Label("Photos Library", systemImage: "photo.on.rectangle.angled")
                }

                Button {
                } label: {
                    Label("Attach Files", systemImage: "paperclip")
                }
            }
            .labelStyle(.titleAndIcon)
        } label: {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.secondary, .clear)
                .font(.largeTitle).fontWeight(.semibold)
                .glassEffect()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
