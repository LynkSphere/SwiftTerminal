import SwiftUI

// MARK: - Claude Label

struct ClaudeLabel: View {
    @Environment(\.colorScheme) var colorScheme

    private let claudeColor = "#D6683B"

    var body: some View {
        Label {
            Text("Claude")
                .font(.subheadline)
                .bold()
                .foregroundStyle(.secondary)
                .foregroundStyle(Color(hex: claudeColor))
                .brightness(colorScheme == .dark ? 1.1 : -0.5)
        } icon: {
            Image("claude.symbols")
                .imageScale(.large)
                .foregroundStyle(Color(hex: claudeColor).gradient)
        }
        .labelIconToTitleSpacing(5)
    }
}

// MARK: - Tool Group (collapsed popover)

struct ToolGroupView: View {
    let tools: [ToolUseInfo]
    @State private var showingPopover = false

    var body: some View {
        Button {
            showingPopover.toggle()
        } label: {
            HStack(spacing: 6) {
                ForEach(uniqueCategories, id: \.iconName) { cat in
                    Image(systemName: cat.iconName)
                }

                Text(summary)
                    .lineLimit(1)

                if hasRunningTool {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .popover(isPresented: $showingPopover) {
            toolList
        }
    }

    private var toolList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(tools) { tool in
                    HStack(spacing: 6) {
                        Image(systemName: tool.category.iconName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 14)

                        Text(tool.name)
                            .font(.caption)
                            .fontWeight(.medium)

                        Text(tool.inputSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Spacer()

                        if !tool.isComplete {
                            ProgressView()
                                .scaleEffect(0.35)
                                .frame(width: 10, height: 10)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
            .contentMargins(10)
        }
        .frame(maxHeight: 300)
    }

    private var summary: String {
        if tools.count == 1 {
            return "\(tools[0].name): \(tools[0].inputSummary)"
        }
        return "\(tools.count) tool calls"
    }

    private var uniqueCategories: [ToolCategory] {
        var seen = Set<String>()
        return tools.compactMap { tool in
            let icon = tool.category.iconName
            if seen.contains(icon) { return nil }
            seen.insert(icon)
            return tool.category
        }
    }

    private var hasRunningTool: Bool {
        tools.contains { !$0.isComplete }
    }
}
