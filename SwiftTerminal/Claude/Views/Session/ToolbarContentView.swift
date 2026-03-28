import SwiftUI

struct ToolbarContentView: ToolbarContent {
    let service: ClaudeService

    @State private var showToolbarItems = false
    @State private var showingSessions = false

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
                if service.isStreaming {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 14, height: 14)
                }
            }

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

            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingSessions = true
                    Task { await service.listSessions() }
                } label: {
                    Label("Sessions", systemImage: "clock.arrow.circlepath")
                }
                .popover(isPresented: $showingSessions) {
                    SessionListView(
                        sessions: service.availableSessions,
                        onResume: { id in
                            showingSessions = false
                            service.resumeSession(id)
                        }
                    )
                }
            }

            if service.session.sessionID != nil {
                ToolbarSpacer(.fixed)

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        service.clearSession()
                    } label: {
                        Label("New Session", systemImage: "plus")
                    }
                }
            }

//            if service.session.isCompacting {
//                ToolbarItem(placement: .primaryAction) {
//                    HStack(spacing: 4) {
//                        ProgressView()
//                            .scaleEffect(0.4)
//                            .frame(width: 12, height: 12)
//                        Text("Compacting...")
//                            .font(.caption2)
//                            .foregroundStyle(.orange)
//                    }
//                }
//            }
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
