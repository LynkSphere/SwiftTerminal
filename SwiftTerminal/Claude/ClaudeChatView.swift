import SwiftUI

struct ClaudeChatView: View {
    let service: ClaudeService
    @State private var input = ""

    var body: some View {
        List {
            if service.messages.isEmpty {
                EmptyStateView(onContinue: service.session.sessionID == nil ? {
                    service.continueLastSession()
                } : nil)
            } else {
                MessageListView(service: service)
            }

            if let approval = service.pendingApproval {
                ApprovalPanelView(
                    approval: approval,
                    onAllow: { service.respondToApproval(allow: true) },
                    onAllowForSession: { service.respondToApproval(allow: true, forSession: true) },
                    onDeny: { service.respondToApproval(allow: false) }
                )
            }

            if let elicitation = service.pendingElicitation {
                ElicitationPanelView(
                    elicitation: elicitation,
                    onAccept: { content in
                        service.respondToElicitation(action: "accept", content: content)
                    },
                    onDecline: {
                        service.respondToElicitation(action: "decline")
                    }
                )
            }

            if let error = service.error {
                errorBar(error)
            }

            if !service.promptSuggestions.isEmpty && !service.isStreaming {
                promptSuggestionsBar
            }
        }
        .toolbar {
            ToolbarContentView(service: service)
        }
        .safeAreaBar(edge: .bottom) {
            InputBarView(input: $input, service: service, onSend: sendMessage)
        }
    }

    private func sendMessage() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !service.isStreaming else { return }
        input = ""
        service.send(trimmed)
    }

    private var promptSuggestionsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(service.promptSuggestions, id: \.self) { suggestion in
                    Button {
                        input = suggestion
                        sendMessage()
                    } label: {
                        Text(suggestion)
                            .font(.caption)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quaternary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }

    private func errorBar(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
            Spacer()
            Button {
                service.error = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.red.opacity(0.05))
    }
}
