import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(WorkspaceStore.self) private var store
    @State private var searchText = ""
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showingOnboarding = false

    var body: some View {
        NavigationSplitView(columnVisibility: Bindable(appState).sidebarVisibility) {
            WorkspaceListView(searchText: searchText)
                .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 300)
                .searchable(text: $searchText, placement: .sidebar, prompt: "Filter workspaces")
        } detail: {
            if let workspace = appState.selectedWorkspace {
                WorkspaceDetailView(workspace: workspace)
                    // .id(workspace.id)
            } else {
                ContentUnavailableView(
                    "No Workspace Selected",
                    systemImage: "sidebar.left",
                    description: Text("Select a workspace to get started.")
                )
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            }
        }
        .inspector(isPresented: Bindable(appState).showingInspector) {
            if let workspace = appState.selectedWorkspace {
                InspectorView(workspace: workspace)
                    .environment(workspace.editorPanel)
                    // .id(workspace.url)
                    .inspectorColumnWidth(min: 240, ideal: 240, max: 360)
            } else {
                ContentUnavailableView(
                    "No Inspector",
                    systemImage: "sidebar.right"
                )
            }
        }
        .focusedSceneValue(\.editorPanel, appState.selectedWorkspace?.editorPanel)
        .focusedSceneValue(\.isMainWindow, true)
        .sheet(isPresented: $showingOnboarding) {
            hasCompletedOnboarding = true
        } content: {
            OnboardingView()
        }
        .task {
            if !hasCompletedOnboarding {
                showingOnboarding = true
            }
        }
        .alert(
            "Replace running command?",
            isPresented: Binding(
                get: { appState.pendingRunReplacement != nil },
                set: { if !$0 { appState.pendingRunReplacement = nil } }
            ),
            presenting: appState.pendingRunReplacement
        ) { command in
            Button("Replace", role: .confirm) {
                command.interrupt()
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    command.workspace?.runCommand(command)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: { command in
            Text("\"\(command.title)\" is currently running. Replacing will stop it and start a new instance.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToSession)) { notification in
            guard let workspaceID = notification.userInfo?["workspaceID"] as? String,
                  let terminalID = notification.userInfo?["terminalID"] as? String else { return }

            if let workspace = store.workspaces.first(where: { $0.id.uuidString == workspaceID }) {
                appState.selectedWorkspace = workspace
                if let terminal = workspace.terminals.first(where: { $0.id.uuidString == terminalID }) {
                    appState.selectedTerminal = terminal
                }
            }
        }
    }
}
