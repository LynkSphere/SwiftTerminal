import SwiftUI

struct EmptyStateView: View {
    var onContinue: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Claude Code")
                .font(.title2)
                .fontWeight(.medium)
            Text("Ask anything about this workspace")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                hintItem(icon: "arrow.up.circle", text: "Enter to send")
                hintItem(icon: "escape", text: "Esc to deny")
                hintItem(icon: "clock.arrow.circlepath", text: "Resume sessions")
            }
            .padding(.top, 8)

            if let onContinue {
                Button("Continue Last Session", action: onContinue)
                    .buttonStyle(.link)
                    .font(.subheadline)
                    .padding(.top, 4)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func hintItem(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2)
        }
        .foregroundStyle(.quaternary)
    }
}
