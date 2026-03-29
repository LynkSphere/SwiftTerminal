import SwiftUI

struct ToolbarContentView: ToolbarContent {
    let service: ClaudeService
    @Environment(AppState.self) private var appState

    @State private var showToolbarItems = false

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Color.clear
                .frame(width: 0, height: 0)
                .task {
                    try? await Task.sleep(for: .seconds(0.2))
                    showToolbarItems = true
                }
        }

        if showToolbarItems {
//            if service.session.contextMaxTokens > 0 {
//                ToolbarItem(placement: .navigation) {
//                    ContextRing(fraction: service.session.contextPercentage / 100)
//                        .help("\(Int(service.session.contextPercentage))% context used")
//                }
//                .sharedBackgroundVisibility(.hidden)
//            }

            ToolbarSpacer(.fixed)

            ToolbarItem(placement: .primaryAction) {
                Picker(selection: Binding(
                    get: { service.selectedEffort },
                    set: { service.selectedEffort = $0 }
                )) {
                    ForEach(EffortLevel.allCases, id: \.self) { effort in
                        Label(effort.label, systemImage: effort.systemImage)
                            .tag(effort)
                    }
                } label: {
                    Label("Effort", systemImage: "gauge.with.needle")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .disabled(service.queryActive)
                .help(service.queryActive ? "Effort can only be changed before starting a session" : "Set reasoning effort level")
            }

            ToolbarSpacer(.fixed)

            ToolbarItem(placement: .primaryAction) {
                modelMenu
            }

            ToolbarSpacer(.fixed)

            ToolbarItem(placement: .primaryAction) {
                permissionMenu
            }
            
            ToolbarSpacer(.fixed)
        }
    }

    // MARK: - Menus

    private var modelMenu: some View {
        Picker(selection: Binding(
            get: { service.selectedModel },
            set: { service.setModel($0) }
        )) {
            ForEach(ModelOption.allCases, id: \.self) { model in
                Label(model.label, image: "claude.symbols")
                    .labelStyle(.titleAndIcon)
                    .tag(model)
            }
        } label: {
            Label(service.selectedModel.label, image: "claude.symbols")
                .labelStyle(.titleAndIcon)
        }
        .menuOrder(.fixed)
    }

    private var permissionMenu: some View {
        Menu {
            ForEach(PermissionModeOption.allCases, id: \.self) { mode in
                Button {
                    service.setPermissionMode(mode)
                } label: {
                    HStack {
                        Text(mode.label)
                        if mode == service.session.permissionMode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label(service.session.permissionMode.label, systemImage: permissionIcon)
        }
    }

    // MARK: - Helpers

    private var permissionIcon: String {
        switch service.session.permissionMode {
        case .default: "shield.lefthalf.filled"
        case .acceptEdits: "shield.checkered"
        case .plan: "doc.text.magnifyingglass"
        case .bypassPermissions: "shield.slash"
        }
    }

    private var permissionColor: Color {
        switch service.session.permissionMode {
        case .default: .secondary
        case .acceptEdits: .orange
        case .plan: .blue
        case .bypassPermissions: .red
        }
    }
}

private struct ContextRing: View {
    var fraction: Double

    private let lineWidth: CGFloat = 3
    private let size: CGFloat = 18

    var body: some View {
        ZStack {
            Circle()
                .stroke(.tertiary, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            Circle()
                .trim(from: 0, to: min(fraction, 1.0))
                .stroke(.blue, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}
