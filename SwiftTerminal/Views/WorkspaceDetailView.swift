import SwiftUI

struct WorkspaceDetailView: View {
    let workspace: Workspace
    @Environment(AppState.self) private var appState
    @State private var showingScratchPad = false

    var body: some View {
        Group {
            if let chat = appState.selectedSession {
                ACPView(chat: chat)
                    .id(chat.id)
            } else {
                SessionBrowserView(workspace: workspace)
                    .id(workspace.id)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomSheetView(directoryURL: workspace.url)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showingScratchPad = true
                } label: {
                    Label("Scratch Pad", systemImage: "note.text")
                }
                .keyboardShortcut(".")
            }
        }
        .sheet(isPresented: $showingScratchPad) {
            ScratchPadSheet(workspace: workspace)
        }
        .navigationTitle(workspace.name)
        .navigationSubtitle(workspace.directory.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
        .environment(workspace.editorPanel)
        .environment(\.showInFileTree) { url in
            workspace.inspectorState.revealInFileTree(url, relativeTo: workspace.url)
        }
    }
}
