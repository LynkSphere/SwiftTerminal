import SwiftUI

struct SessionBarView: View {
    let session: SessionInfo
    let isStreaming: Bool
    let selectedModel: ModelOption
    let selectedEffort: EffortLevel
    let selectedContextWindow: ContextWindow
    let availableSessions: [SessionSummary]
    let onClear: () -> Void
    let onContinueLast: () -> Void
    let onListSessions: () -> Void
    let onResume: (String) -> Void
    let onModelChange: (ModelOption) -> Void
    let onEffortChange: (EffortLevel) -> Void
    let onContextWindowChange: (ContextWindow) -> Void
    let onPermissionModeChange: (PermissionModeOption) -> Void

    @State private var showingSessions = false
    @State private var showingSettings = false

    var body: some View {
        HStack(spacing: 8) {
            if isStreaming {
                ProgressView()
                    .scaleEffect(0.4)
                    .frame(width: 12, height: 12)
            }

            modelButton

            effortPicker

            contextWindowPicker

            if session.turnCount > 0 {
                Text("\(session.turnCount) turns")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if session.totalCost > 0 {
                Text(formatCost(session.totalCost))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fontDesign(.monospaced)
            }

            if session.isCompacting {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.35)
                        .frame(width: 10, height: 10)
                    Text("Compacting...")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            permissionPicker

            Button {
                showingSessions = true
                onListSessions()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .popover(isPresented: $showingSessions) {
                SessionListView(
                    sessions: availableSessions,
                    onResume: { id in
                        showingSessions = false
                        onResume(id)
                    }
                )
            }

            if session.sessionID == nil {
                Button("Continue", action: onContinueLast)
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
            }

            if session.sessionID != nil {
                Button("New", action: onClear)
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
    }

    private var modelButton: some View {
        Menu {
            ForEach(ModelOption.allCases, id: \.self) { model in
                Button {
                    onModelChange(model)
                } label: {
                    HStack {
                        Text(model.label)
                        if model == selectedModel {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Text(formatModel(session.model, fallback: selectedModel))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fontDesign(.monospaced)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var effortPicker: some View {
        Menu {
            ForEach(EffortLevel.allCases, id: \.self) { effort in
                Button {
                    onEffortChange(effort)
                } label: {
                    HStack {
                        Text(effort.label)
                        if effort == selectedEffort {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Text(selectedEffort.label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var contextWindowPicker: some View {
        Menu {
            ForEach(ContextWindow.allCases, id: \.self) { window in
                Button {
                    onContextWindowChange(window)
                } label: {
                    HStack {
                        Text(window.label)
                        if window == selectedContextWindow {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Text(selectedContextWindow.label)
                .font(.caption2)
//                .foregroundStyle(selectedContextWindow == .extended ? .blue : .tertiary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var permissionPicker: some View {
        Menu {
            ForEach(PermissionModeOption.allCases, id: \.self) { mode in
                Button {
                    onPermissionModeChange(mode)
                } label: {
                    VStack(alignment: .leading) {
                        HStack {
                            Text(mode.label)
                            if mode == session.permissionMode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: permissionIcon)
                .font(.caption2)
                .foregroundStyle(permissionColor)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var permissionIcon: String {
        switch session.permissionMode {
        case .default: "shield.lefthalf.filled"
        case .acceptEdits: "shield.checkered"
        case .plan: "doc.text.magnifyingglass"
        case .bypassPermissions: "shield.slash"
        }
    }

    private var permissionColor: Color {
        switch session.permissionMode {
        case .default: .secondary
        case .acceptEdits: .orange
        case .plan: .blue
        case .bypassPermissions: .red
        }
    }

    private func formatModel(_ model: String?, fallback: ModelOption) -> String {
        guard let model else { return fallback.label.lowercased() }
        if model.contains("opus") { return "opus 4.6" }
        if model.contains("sonnet") { return "sonnet 4.6" }
        if model.contains("haiku") { return "haiku 4.5" }
        return model
    }

    private func formatCost(_ cost: Double) -> String {
        if cost < 0.01 {
            return String(format: "$%.4f", cost)
        }
        return String(format: "$%.2f", cost)
    }
}
