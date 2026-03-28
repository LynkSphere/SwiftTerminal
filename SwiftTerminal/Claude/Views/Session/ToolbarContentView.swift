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
                Text(model.label).tag(model)
            }
        } label: {
            Text(service.selectedModel.label)
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
            Image(systemName: permissionIcon)
                .foregroundStyle(permissionColor)
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
