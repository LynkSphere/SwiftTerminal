import SwiftUI

struct InputBarView: View {
    let service: ClaudeService
    @FocusState private var isFocused: Bool

    var body: some View {
        GlassEffectContainer {
            HStack(alignment: .bottom) {
                ZStack(alignment: .leading) {
                    if service.prompt.isEmpty {
                        Text("Make Claude do anything...")
                            .padding(.leading, 1)
                            .foregroundStyle(.placeholder)
                    }

                    TextEditor(text: Bindable(service).prompt)
                        .padding(.leading, -4)
                        .frame(maxHeight: 350)
                        .fixedSize(horizontal: false, vertical: true)
                        .scrollContentBackground(.hidden)
                        .disabled(service.pendingApproval != nil)
                }
                .font(.body)
                .focused($isFocused)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .padding(6)
                .glassEffect(in: .rect(cornerRadius: 16))

                Button {
                    service.isStreaming ? service.stop() : service.sendMessage()
                } label: {
                    Image(systemName: service.isStreaming ? "stop.fill" : "arrow.up")
                        .font(.system(size: 15)).fontWeight(.bold)
                }
                .opacity(0.85)
                .controlSize(.large)
                .tint(service.isStreaming ? .red : .accent)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .disabled(!service.isStreaming && trimmedPrompt.isEmpty)
                .offset(y: -2)
                .keyboardShortcut(service.isStreaming ? "d" : .return)
            }
            .padding(10)
        }
        .task { isFocused = true }
    }

    private var trimmedPrompt: String {
        service.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
