import SwiftUI

struct WorkspaceDetailView: View {
    let workspace: Workspace
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack {
            if let terminal = appState.selectedTerminal {
                TerminalContainerRepresentable(tab: terminal)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .navigationTitle(workspace.name)
        .navigationSubtitle(workspace.directory.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
        .safeAreaBar(edge: .top, spacing: 0) {
            if workspace.terminals.count > 1 {
                DocumentTabBar(workspace: workspace)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomSheetView(directoryURL: workspace.url)
        }
        .task(id: workspace) {
            appState.selectedTerminal = workspace.terminals.first ?? workspace.addTerminal()
        }
    }
}
