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
                        .font(.caption2)
                }

                Text(summary)
                    .font(.caption)
                    .lineLimit(1)

                if hasRunningTool {
                    ProgressView()
                        .scaleEffect(0.4)
                        .frame(width: 10, height: 10)
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
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
            .padding(10)
        }
        .frame(width: 350, height: 300)
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

// MARK: - Expandable Text

struct ExpandableText: View {
    let text: String
    let maxCharacters: Int

    @State private var isExpanded = false
    private let needsExpansion: Bool

    init(text: String, maxCharacters: Int = 400) {
        self.text = text
        self.maxCharacters = maxCharacters
        self.needsExpansion = text.count > maxCharacters
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(displayedText)
                .textSelection(.enabled)
                .lineSpacing(2)

            if needsExpansion {
                Button {
                    isExpanded.toggle()
                } label: {
                    Text(isExpanded ? "Show Less" : "Show More")
                }
                .buttonBorderShape(.capsule)
            }
        }
    }

    private var displayedText: String {
        guard needsExpansion && !isExpanded else { return text }
        return String(text.prefix(maxCharacters))
    }
}

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (r, g, b, a) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
