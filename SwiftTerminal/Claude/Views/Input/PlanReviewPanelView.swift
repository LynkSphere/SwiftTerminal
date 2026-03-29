import SwiftUI

struct PlanReviewPanelView: View {
    let service: ClaudeService
    @State private var feedback = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.blue)

                Text("Plan Ready")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.blue)
            }

            Text("Review the plan above, then choose how to proceed")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("Full Auto") {
                    service.acceptPlan(mode: .bypassPermissions)
                }
                .keyboardShortcut(.return, modifiers: .command)

                Button("Accept Edits") {
                    service.acceptPlan(mode: .acceptEdits)
                }
                .keyboardShortcut(.return, modifiers: [])

                Button("Default") {
                    service.acceptPlan(mode: .default)
                }
            }
            .controlSize(.small)

            HStack(spacing: 8) {
                TextField("Discuss the plan...", text: $feedback, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused($isFocused)
                    .onSubmit { submitFeedback() }

                Button("Send") { submitFeedback() }
                    .disabled(feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .overlay(alignment: .top) { Divider() }
    }

    private func submitFeedback() {
        let text = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        feedback = ""
        service.discussPlan(text)
    }
}
