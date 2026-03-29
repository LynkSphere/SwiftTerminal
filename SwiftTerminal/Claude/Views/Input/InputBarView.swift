import SwiftUI

struct InputBarView: View {
    let service: ClaudeService
    @FocusState var isFocused: Bool

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 0) {
                if !service.imageAttachments.isEmpty {
                    attachmentPreview
                }

                HStack(alignment: .bottom) {
                    AttachmentMenuView(service: service)

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
                    .disabled(!service.isStreaming && !canSend)
                    .offset(y: -2)
                    .keyboardShortcut(service.isStreaming ? "d" : .return)
                }
                .padding(10)
            }
        }
        .task { isFocused = true }
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                Button {
                    isFocused = true
                } label: {
                    EmptyView()
                }
                .keyboardShortcut("l", modifiers: .command)
            }
        }
    }

    private var canSend: Bool {
        !trimmedPrompt.isEmpty || !service.imageAttachments.isEmpty
    }

    private var trimmedPrompt: String {
        service.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var attachmentPreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(service.imageAttachments) { attachment in
                    ZStack(alignment: .topTrailing) {
                        if let nsImage = NSImage(data: attachment.data) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        Button {
                            service.imageAttachments.removeAll { $0.id == attachment.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.white, .black.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 4, y: -4)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)
        }
    }
}
