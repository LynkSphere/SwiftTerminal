import SwiftUI

struct SessionListView: View {
    let sessions: [SessionSummary]
    let onResume: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Resume Session")
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            Divider()

            if sessions.isEmpty {
                Text("Loading sessions...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(sessions) { session in
                            SessionRow(session: session, onResume: onResume)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .frame(width: 280)
    }
}

private struct SessionRow: View {
    let session: SessionSummary
    let onResume: (String) -> Void

    var body: some View {
        Button {
            onResume(session.id)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title ?? session.id.prefix(8).description)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let lastActive = session.lastActive {
                        Text(formatDate(lastActive))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if session.messageCount > 0 {
                        Text("\(session.messageCount) msgs")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func formatDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else {
            return iso.prefix(10).description
        }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .short
        return relative.localizedString(for: date, relativeTo: Date())
    }
}
