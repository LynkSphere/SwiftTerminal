import SwiftUI

struct WorkspaceDetailView: View {
    @Bindable var workspace: Workspace
    @Environment(AppState.self) private var appState
    @FocusState private var isTerminalFocused: Bool
    @State private var editorPanel = EditorPanel()
    @AppStorage("editorPanelHeight") private var panelHeight: Double = 250

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                TerminalContainerRepresentable(
                    tabs: workspace.tabs,
                    selectedTab: workspace.selectedTab
                )
                .focusable()
                .focusEffectDisabled()
                .focused($isTerminalFocused)
                .containerRelativeFrame(.vertical)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if editorPanel.isOpen {
                PanelDragHandle(panelHeight: $panelHeight)
                editorPanelView
                    .frame(height: panelHeight)
            }
        }
        .navigationTitle(workspace.name)
        .navigationSubtitle(workspace.selectedTab?.displayDirectory ?? "")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: workspace.selectedTab?.id) {
            focusTerminal()
        }
        .safeAreaBar(edge: .top, spacing: 0) {
            if workspace.tabs.count > 1 {
                DocumentTabBar(workspace: workspace)
            }
        }
        .inspector(isPresented: Bindable(appState).showingInspector) {
            if let directory = workspace.directory {
                InspectorView(directoryURL: URL(fileURLWithPath: directory))
                    .inspectorColumnWidth(min: 180, ideal: 220, max: 360)
            }
        }
        .environment(editorPanel)
    }

    @ViewBuilder
    private var editorPanelView: some View {
        let dir = workspace.directory.map { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: "/")
        switch editorPanel.content {
        case .file(let url):
            FileEditorPanel(fileURL: url, directoryURL: dir)
        case .diff(let reference):
            DiffPanel(reference: reference, directoryURL: dir)
        case .none:
            EmptyView()
        }
    }

    private func focusTerminal() {
        guard workspace.selectedTab != nil else { return }

        DispatchQueue.main.async {
            isTerminalFocused = true
        }
    }
}

// MARK: - Drag Handle

private struct PanelDragHandle: View {
    @Binding var panelHeight: Double

    var body: some View {
        Divider()
            .overlay {
                Rectangle()
                    .fill(.clear)
                    .frame(height: 8)
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
}

private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}
