import SwiftUI
import UniformTypeIdentifiers

struct ComposeThreadView: View {
    @Environment(AgentIntegrationStore.self) private var integrations
    @Environment(WorkspaceStore.self) private var store
    @Environment(AppState.self) private var appState
    @Environment(TaskSessionController.self) private var sessions
    @Environment(\.dismiss) private var dismiss
    @State private var provider = AgentProvider.codex
    @State private var workspaceID: UUID?
    @State private var showingProjectPicker = false

    var body: some View {
        VStack(alignment: .leading) {
            Text("New Task").font(.title2).bold()
            Form {
                Picker("Open with", selection: $provider) {
                    ForEach(integrations.enabledProviders) { provider in
                        Text(provider.name).tag(provider)
                    }
                }
                Picker("Project", selection: $workspaceID) {
                    Text("Choose a project").tag(UUID?.none)
                    ForEach(store.workspaces) { workspace in
                        Text(workspace.name).tag(Optional(workspace.id))
                    }
                }
                if let workspace = store.workspaces.first(where: { $0.id == workspaceID }) {
                    Text(workspace.directory).font(.caption).foregroundStyle(.secondary)
                }
                Button("Add Project…", systemImage: "folder.badge.plus") { showingProjectPicker = true }
            }
            .disabled(sessions.isOpening)
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(sessions.isOpening)
                Spacer()
                if sessions.isOpening { ProgressView().controlSize(.small) }
                Button("Open Task") {
                    guard let workspace = store.workspaces.first(where: { $0.id == workspaceID }) else { return }
                    Task {
                        if await sessions.compose(provider: provider, workspace: workspace) { dismiss() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(workspaceID == nil || sessions.isOpening || !integrations.enabledProviders.contains(provider))
            }
        }
        .padding()
        .frame(width: 420)
        .interactiveDismissDisabled(sessions.isOpening)
        .alert("Couldn’t Open Thread", isPresented: Binding(
            get: { integrations.actionError != nil },
            set: { if !$0 { integrations.actionError = nil } }
        )) {
            Button("OK") { integrations.actionError = nil }
        } message: {
            Text(integrations.actionError ?? "")
        }
        .fileImporter(isPresented: $showingProjectPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { addProject(url) }
        }
        .onAppear {
            provider = integrations.enabledProviders.first ?? .codex
            workspaceID = appState.selectedWorkspace?.id ?? store.workspaces.first?.id
        }
    }

    private func addProject(_ url: URL) {
        if let existing = store.workspaces.first(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
            workspaceID = existing.id
            return
        }
        let workspace = Workspace(name: url.lastPathComponent, directory: url.path)
        workspace.detectProjectType()
        store.addWorkspace(workspace)
        workspaceID = workspace.id
    }
}
