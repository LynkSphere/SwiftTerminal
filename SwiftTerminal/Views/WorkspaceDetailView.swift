#if os(macOS)
import SwiftUI

struct WorkspaceDetailView: View {
    @Bindable var workspace: Workspace

    var body: some View {
        ScrollView {
            terminalContent
                .frame(maxWidth: .infinity)
                .containerRelativeFrame(.vertical)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .backgroundExtensionEffect()
        .scrollClipDisabled()
        .safeAreaBar(edge: .top, spacing: 0) {
            DocumentTabBar(workspace: workspace)
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
        }
    }
}
#endif
