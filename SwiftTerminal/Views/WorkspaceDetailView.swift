import SwiftUI

struct WorkspaceDetailView: View {
    @Bindable var workspace: Workspace
    @Environment(AppState.self) private var appState
    @State private var editorPanel = EditorPanel()
    @AppStorage("editorPanelHeight") private var panelHeight: Double = 250

    private var service: ClaudeService {
        appState.claudeService(for: workspace)
    }

    var body: some View {
        VStack(spacing: 0) {
            ClaudeChatView(service: service)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if editorPanel.content != nil {
                Rectangle()
                    .fill(Color(nsColor: .gridColor))
                    .frame(height: 1)
                    .overlay {
                        if editorPanel.isOpen {
                            Rectangle()
                                .fill(.clear)
                                .frame(height: 20)
                                .contentShape(Rectangle())
                                .cursor(.resizeUpDown)
                                .gesture(
                                    DragGesture(minimumDistance: 1)
                                        .onChanged { value in
                                            let delta = -value.translation.height
                                            panelHeight = max(100, panelHeight + delta)
                                        }
                                )
                        }
                    }
                BottomSheetView(
                    directoryURL: workspace.directory.map { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: "/")
                )
                .frame(height: editorPanel.isOpen ? panelHeight : 30, alignment: .top)
            }
        }
        .navigationTitle(workspace.name)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

//    private func focusTerminal() {
//        guard workspace.selectedTab != nil else { return }
//
//        DispatchQueue.main.async {
//            isTerminalFocused = true
//        }
//    }
}

private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}
