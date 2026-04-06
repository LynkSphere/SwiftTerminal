import SwiftUI

struct WorkspaceDetailView: View {
    let workspace: Workspace
    @Environment(AppState.self) private var appState
    @State private var showingScratchPad = false

    var body: some View {
        VStack {
            if let terminal = appState.selectedTerminal {
                TerminalContainerRepresentable(tab: terminal, appState: appState)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, 30)
            }
        }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showingScratchPad = true
                } label: {
                    Label("Scratch Pad", systemImage: "note.text")
                }
            }
        }
        .sheet(isPresented: $showingScratchPad) {
            ScratchPadSheet(workspace: workspace)
        }
        .navigationTitle(workspace.name)
        .navigationSubtitle(workspace.directory.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
        .safeAreaBar(edge: .top, spacing: 0) {
            DocumentTabBar(workspace: workspace)
        }
        .overlay(alignment: .bottom) {
            BottomSheetView(directoryURL: workspace.url)
        }
        .environment(workspace.editorPanel)
        .environment(\.showInFileTree) { url in
            workspace.inspectorState.revealInFileTree(url, relativeTo: workspace.url)
        }
        .task(id: workspace) {
            appState.selectedTerminal = workspace.terminals.first ?? workspace.addTerminal()
        }
        .onChange(of: appState.selectedTerminal) {
            appState.selectedTerminal?.hasBellNotification = false
        }
        .alert(
            "Close Tab?",
            isPresented: Binding(
                get: { appState.terminalPendingClose != nil },
                set: { if !$0 { appState.terminalPendingClose = nil } }
            )
        ) {
            Button("Close", role: .destructive) {
                guard let terminal = appState.terminalPendingClose else { return }
                let next = workspace.terminalAfter(terminal) ?? workspace.terminalBefore(terminal)
                workspace.closeTerminal(terminal)
                if appState.selectedTerminal === terminal {
                    appState.selectedTerminal = next
                }
                appState.terminalPendingClose = nil
            }
            Button("Cancel", role: .cancel) {
                appState.terminalPendingClose = nil
            }
        } message: {
            if let terminal = appState.terminalPendingClose, let name = terminal.foregroundProcessName {
                Text("\"\(name)\" is still running in this tab. Are you sure you want to close it?")
            } else {
                Text("A process is still running in this tab. Are you sure you want to close it?")
            }
        }
    }
}
