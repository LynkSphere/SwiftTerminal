import SwiftUI

struct WorkspaceDetailView: View {
    @Bindable var workspace: Workspace
    @FocusState private var isTerminalFocused: Bool
    @State private var showingInspector = false

    var body: some View {
        ScrollView {
            TerminalContainerRepresentable(
                tabs: workspace.tabs,
                selectedTab: workspace.selectedTab
            )
            .focusable()
            .focused($isTerminalFocused)
                .containerRelativeFrame(.vertical)
        }
        .navigationTitle(workspace.name)
        .navigationSubtitle(workspace.selectedTab?.displayDirectory ?? "")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: workspace.selectedTab?.id) {
            focusTerminal()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingInspector.toggle()
                } label: {
                    Image(systemName: "sidebar.trailing")
                }
            }
        }
        .safeAreaBar(edge: .top, spacing: 0) {
            if workspace.tabs.count > 1 {
                DocumentTabBar(workspace: workspace)
            }
        }
        .inspector(isPresented: $showingInspector) {
            if let directory = workspace.directory {
                FileTreeView(directoryURL: URL(fileURLWithPath: directory))
                    .inspectorColumnWidth(min: 180, ideal: 220, max: 360)
            }
        }
    }

    private func focusTerminal() {
        guard workspace.selectedTab != nil else { return }

        DispatchQueue.main.async {
            isTerminalFocused = true
        }
    }
}
