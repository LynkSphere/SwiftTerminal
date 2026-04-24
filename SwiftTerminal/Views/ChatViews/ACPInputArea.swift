import SwiftUI
import ACPModel

struct ACPInputArea: View {
    @Bindable var chat: Chat
    @FocusState private var isFocused: Bool

    private var session: ACPSession { chat.session }

    private var canSend: Bool {
        !chat.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !chat.pendingAttachments.isEmpty
    }

    private var attributedPrompt: Binding<AttributedString> {
        Binding(
            get: {
                var attributed = AttributedString(chat.prompt)
                highlightCommand(in: &attributed)
                return attributed
            },
            set: { newValue in
                chat.prompt = String(newValue.characters)
            }
        )
    }

    private func highlightCommand(in text: inout AttributedString) {
        let plain = String(text.characters)
        guard plain.hasPrefix("/") else { return }

        let afterSlash = plain.dropFirst()
        let token = String(afterSlash.prefix(while: { !$0.isWhitespace })).lowercased()
        guard !token.isEmpty else { return }

        let matched = session.availableCommands.contains { $0.name.lowercased() == token }
        guard matched else { return }

        let commandLength = 1 + token.count // "/" + command name
        let startIndex = text.startIndex
        let endIndex = text.index(startIndex, offsetByCharacters: commandLength)
        text[startIndex..<endIndex].foregroundColor = .accentColor
        text[startIndex..<endIndex].font = .body.bold()
    }

    var body: some View {
        GlassEffectContainer {
            HStack(alignment: .bottom) {
                ACPInputMenu(chat: chat)
                    .offset(y: -1)

                VStack(alignment: .leading) {
                    if !chat.pendingAttachments.isEmpty {
                        AttachmentThumbnails(chat: chat)
                    }

                    TextEditor(text: attributedPrompt)
                        .padding(.leading, -4)
                        .frame(maxHeight: 350)
                        .fixedSize(horizontal: false, vertical: true)
                        .scrollContentBackground(.hidden)
                        .focused($isFocused)
                        .overlay(alignment: .leading) {
                             if chat.prompt.isEmpty {
                                 Text("Message \(chat.provider.rawValue)...")
                                    .padding(.leading, 1)
                                    .foregroundStyle(.placeholder)
                                    .allowsHitTesting(false)
                             }
                        }
                       .font(.body)
                }
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
                .disabled(!session.isProcessing && (!canSend || session.isConnecting))
                .offset(y: -2)
                .keyboardShortcut(session.isProcessing ? "d" : .return, modifiers: [.command])
            }
            .padding(12)
        }
        .imagePasteHandler(chat: chat)
        .toolbar {
            ToolbarItem(placement: .keyboard) {
               Button("Focus") {
                   isFocused = true
               }
               .keyboardShortcut("l")
            }
        }
        .task {
            isFocused = true
        }
    }

    private func send() {
        let text = chat.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = chat.pendingAttachments
        guard !text.isEmpty || !attachments.isEmpty else { return }
        chat.prompt = ""
        chat.sendMessage(text, attachments: attachments)
    }
}
