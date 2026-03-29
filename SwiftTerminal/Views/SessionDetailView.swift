import SwiftUI

struct SessionDetailView: View {
    var session: ClaudeSession
    @Environment(AppState.self) private var appState
    @State private var editorPanel = EditorPanel()

    private var workspace: Workspace? { session.workspace }

    var body: some View {
        if let workspace {
            let service = session.resolveService()
            ClaudeChatView(service: service)
                .task {
                    if service.messages.isEmpty, let sessionID = service.session.sessionID {
                        service.resumeSession(sessionID)
                    }
                }
                .navigationTitle(workspace.name)
                .navigationSubtitle(workspace.directory)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    BottomSheetView(directoryURL: workspace.url)
                }
                .inspector(isPresented: Bindable(appState).showingInspector) {
                    InspectorView(directoryURL: workspace.url)
                        .inspectorColumnWidth(min: 240, ideal: 240, max: 360)
                }
                .environment(editorPanel)
                .onChange(of: appState.panelToggleToken) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        editorPanel.toggle()
                    }
                }
        }
    }
}
