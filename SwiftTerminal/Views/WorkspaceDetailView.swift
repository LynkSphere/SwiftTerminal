import SwiftUI

struct WorkspaceDetailView: View {
    @Bindable var workspace: Workspace
    @FocusState private var isTerminalFocused: Bool
    @State private var showingInfo = false

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
                    showingInfo.toggle()
                } label: {
                    Image(systemName: "info")
                }
                .popover(isPresented: $showingInfo) {
                    WorkspaceInfoView(workspace: workspace)
                }
            }
        }
        .safeAreaBar(edge: .top, spacing: 0) {
            if workspace.tabs.count > 1 {
                DocumentTabBar(workspace: workspace)
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
