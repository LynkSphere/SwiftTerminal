import SwiftUI

struct ApprovalPanelView: View {
    let approval: ApprovalRequest
    let onAllow: () -> Void
    let onAllowForSession: () -> Void
    let onDeny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.caption)
                    .foregroundStyle(.orange)

                Text("Permission Required")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.orange)
            }

            if let title = approval.title {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.primary)
            } else {
                Text("Claude wants to use **\(approval.toolName)**")
                    .font(.caption)
                    .foregroundStyle(.primary)
            }

            if let desc = approval.description {
                Text(desc)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let reason = approval.decisionReason {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .italic()
            }

            if !approval.input.isEmpty {
                inputSummary
            }

            HStack(spacing: 8) {
                Button(action: onAllow) {
                    Text("Allow")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.small)
                .keyboardShortcut(.return, modifiers: [])

                Button(action: onAllowForSession) {
                    Text("Always Allow")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut(.return, modifiers: .shift)

                Button(action: onDeny) {
                    Text("Deny")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.small)
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Text("Enter / Shift+Enter / Esc")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.05))
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder
    private var inputSummary: some View {
        let summary = formatApprovalInput(approval.toolName, approval.input)
        if !summary.isEmpty {
            Text(summary)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(8)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    private func formatApprovalInput(_ tool: String, _ input: [String: Any]) -> String {
        switch tool {
        case "Bash":
            let cmd = (input["command"] as? String) ?? ""
            let desc = (input["description"] as? String)
            if let desc { return "\(desc)\n\(cmd)" }
            return cmd
        case "Write", "Edit", "Read":
            return (input["file_path"] as? String) ?? ""
        default:
            let relevant = input.filter { !["description"].contains($0.key) }
            return relevant.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        }
    }
}
