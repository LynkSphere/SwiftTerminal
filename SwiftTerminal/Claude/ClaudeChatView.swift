import SwiftUI

struct ClaudeChatView: View {
    let service: ClaudeService
    @State private var input = ""

    var body: some View {
        VStack(spacing: 0) {
            SessionBarView(
                session: service.session,
                isStreaming: service.isStreaming,
                selectedModel: service.selectedModel,
                selectedEffort: service.selectedEffort,
                selectedContextWindow: service.selectedContextWindow,
                availableSessions: service.availableSessions,
                onClear: { service.clearSession() },
                onContinueLast: { service.continueLastSession() },
                onListSessions: {
                    Task { await service.listSessions() }
                },
                onResume: { sessionID in
                    service.resumeSession(sessionID)
                },
                onModelChange: { model in
                    service.setModel(model)
                },
                onEffortChange: { effort in
                    service.selectedEffort = effort
                },
                onContextWindowChange: { window in
                    service.setContextWindow(window)
                },
                onPermissionModeChange: { mode in
                    service.setPermissionMode(mode)
                }
            )

            if service.messages.isEmpty {
                EmptyStateView()
            } else {
                MessageListView(
                    messages: service.messages,
                    isStreaming: service.isStreaming,
                    activeTasks: service.activeTasks,
                    onStopTask: { taskID in service.stopTask(taskID) }
                )
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

            InputBarView(
                input: $input,
                isStreaming: service.isStreaming,
                hasApproval: service.pendingApproval != nil,
                onSend: sendMessage,
                onStop: { service.stop() }
            )
        }
        .background(Color(nsColor: .textBackgroundColor))
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
