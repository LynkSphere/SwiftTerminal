import SwiftUI

struct WorkspaceDetailView: View {
    @Bindable var workspace: Workspace
    @FocusState private var isTerminalFocused: Bool

    var body: some View {
        ScrollView {
            terminalContent
                .containerRelativeFrame(.vertical)
                .padding(6)
                .padding(.trailing, -6)
        }
        .navigationTitle(workspace.name)
        .navigationSubtitle(workspace.selectedTab?.displayDirectory ?? "")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
//        .backgroundExtensionEffect()
        .scrollClipDisabled()
        .task(id: workspace.selectedTab?.id) {
            focusTerminal()
        }
        .safeAreaBar(edge: .top, spacing: 0) {
            if workspace.tabs.count > 1 {
                DocumentTabBar(workspace: workspace)
            }
        }
    }

    @ViewBuilder
    private var terminalContent: some View {
        if workspace.tabs.isEmpty {
            ContentUnavailableView("No Terminal", systemImage: "terminal")
        } else {
            TerminalContainerRepresentable(
                tabs: workspace.tabs,
                selectedTab: workspace.selectedTab
            )
            .focusable()
            .focused($isTerminalFocused)
        }
    }

    private func focusTerminal() {
        guard workspace.selectedTab != nil else { return }

        DispatchQueue.main.async {
            isTerminalFocused = true
        }
    }
}
