import SwiftUI

struct WorkspaceDetailView: View {
    @Bindable var workspace: Workspace
    @Environment(AppState.self) private var appState
    @State private var editorPanel = EditorPanel()

    private var service: ClaudeService {
        appState.claudeService(for: workspace)
    }

    var body: some View {
        ClaudeChatView(service: service)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if editorPanel.content != nil {
                    BottomSheetView(
                        directoryURL: workspace.directory.map { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: "/")
                    )
                }
            }
            .navigationTitle(workspace.name)
            .navigationSubtitle(workspace.directory ?? "")
            .inspector(isPresented: Bindable(appState).showingInspector) {
                if let directory = workspace.directory {
                    InspectorView(directoryURL: URL(fileURLWithPath: directory))
                        .inspectorColumnWidth(min: 180, ideal: 220, max: 360)
                }
            }
            .environment(editorPanel)
            .onChange(of: appState.panelToggleToken) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    editorPanel.toggle()
                }
            }
            .onChange(of: service.session.sessionID) { _, newID in
                if let newID {
                    workspace.addClaudeSession(newID)
                }
            }
            .onChange(of: appState.selectedSessionID) { _, sessionID in
                if let sessionID, sessionID != service.session.sessionID {
                    service.resumeSession(sessionID)
                }
            }
            .task {
                // Auto-resume the most recent session if service is fresh
                if service.messages.isEmpty, let lastSessionID = workspace.claudeSessionIDs.last {
                    service.resumeSession(lastSessionID)
                }
            }
    }
}
