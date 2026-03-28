import SwiftUI

struct WorkspaceDetailView: View {
    @Bindable var workspace: Workspace
    @Environment(AppState.self) private var appState
    @State private var editorPanel = EditorPanel()

    var body: some View {
        Group {
            if let service = workspace.activeSession {
                ClaudeChatView(service: service)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if editorPanel.content != nil {
                            BottomSheetView(
                                directoryURL: workspace.directory.map { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: "/")
                            )
                        }
                    }
                    .onChange(of: service.session.sessionID) { _, newID in
                        if let newID {
                            workspace.persistSession(newID)
                        }
                    }
                    .task {
                        if service.messages.isEmpty, let sessionID = service.session.sessionID {
                            service.resumeSession(sessionID)
                        }
                    }
            } else {
                ContentUnavailableView {
                    Label("No Session", systemImage: "bubble.left")
                } description: {
                    Text("Right-click the workspace to start a new session.")
                }
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
        .onChange(of: appState.sidebarSelection) { _, selection in
            switch selection {
            case .session:
                workspace.selectedSession = appState.selectedService
            case .workspace:
                workspace.selectedSession = nil
            case nil:
                break
            }
        }
    }
}
