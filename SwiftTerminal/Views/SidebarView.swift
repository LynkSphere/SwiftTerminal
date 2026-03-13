#if os(macOS)
import SwiftUI

struct SidebarView: View {
    @Bindable var appState: AppState

    var body: some View {
        List(selection: $appState.selectedWorkspace) {
            ForEach(appState.workspaces) { workspace in
                Label(workspace.name, systemImage: "folder")
                    .tag(workspace)
                    .contextMenu {
                        Button("Rename...") {
                            // TODO: rename
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            appState.removeWorkspace(workspace)
                        }
                    }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    appState.addWorkspace()
                } label: {
                    Label("New Workspace", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .padding(8)
                Spacer()
            }
        }
    }
}
#endif
