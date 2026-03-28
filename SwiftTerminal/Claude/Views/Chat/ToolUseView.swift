import SwiftUI

struct ToolUseView: View {
    let info: ToolUseInfo
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: info.category.iconName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    Text(info.name)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    Text(info.inputSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    // File path badge for file-related tools
                    if let filePath = info.fileBadge {
                        Text(filePath)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.blue)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }

                    if let elapsed = info.elapsedSeconds, !info.isComplete {
                        Text(formatElapsed(elapsed))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fontDesign(.monospaced)
                    }

                    statusIndicator

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .padding(.horizontal, 10)

                expandedContent
                    .padding(10)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if info.isComplete {
            if info.result?.content.hasPrefix("Error") == true || info.result?.content.hasPrefix("error") == true {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        } else {
            ProgressView()
                .scaleEffect(0.4)
                .frame(width: 12, height: 12)
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !info.input.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Input")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)

                    Text(formatInput(info.input))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(15)
                }
            }

            if let result = info.result {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Result")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)

                        if let lines = result.numLines {
                            Text("\(lines) lines")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        if let path = result.filePath {
                            Text(shortenPath(path))
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                    }

                    Text(result.content.prefix(3000))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(30)
                }
            }
        }
    }

    private func formatInput(_ input: [String: Any]) -> String {
        let interesting = input.filter { key, _ in
            !["description"].contains(key)
        }
        return interesting.map { key, value in
            "\(key): \(String(describing: value))"
        }.joined(separator: "\n")
    }

    private func formatElapsed(_ seconds: Double) -> String {
        if seconds < 60 {
            return String(format: "%.0fs", seconds)
        }
        return String(format: "%.0fm%.0fs", seconds / 60, seconds.truncatingRemainder(dividingBy: 60))
    }

    private func shortenPath(_ path: String) -> String {
        let components = path.split(separator: "/")
        if components.count <= 2 { return path }
        return components.last.map(String.init) ?? path
    }
}

// MARK: - File Badge Extension

extension ToolUseInfo {
    var fileBadge: String? {
        switch name {
        case "Write", "Edit":
            guard let path = input["file_path"] as? String else { return nil }
            let components = path.split(separator: "/")
            return components.last.map(String.init)
        default:
            return nil
        }
    }
}
