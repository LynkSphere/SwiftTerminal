import SwiftUI

struct InputBarView: View {
    @Binding var input: String
    let service: ClaudeService
    let onSend: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        GlassEffectContainer {
            HStack(alignment: .bottom) {
                Button {
                    // Placeholder action
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.secondary, .clear)
                        .font(.largeTitle).fontWeight(.semibold)
                        .glassEffect()
                }
                .buttonStyle(.plain)
                .offset(y: -1)

                ZStack(alignment: .leading) {
                    if input.isEmpty {
                        Text("Message Claude...")
                            .padding(.leading, 1)
                            .foregroundStyle(.placeholder)
                    }

                    TextEditor(text: $input)
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
                    service.isStreaming ? service.stop() : onSend()
                } label: {
                    Image(systemName: service.isStreaming ? "stop.fill" : "arrow.up")
                        .font(.system(size: 15)).fontWeight(.bold)
                }
                .opacity(0.85)
                .controlSize(.large)
                .tint(service.isStreaming ? .red : .accent)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .disabled(!service.isStreaming && trimmedInput.isEmpty)
                .offset(y: -2)
            }
            .padding(12)
        }
        .task { isFocused = true }
    }

    private var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
