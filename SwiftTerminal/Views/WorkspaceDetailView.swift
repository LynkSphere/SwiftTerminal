import SwiftUI

struct WorkspaceDetailView: View {
    let workspace: Workspace
    @Environment(AppState.self) private var appState
    @State private var showingScratchPad = false

    var body: some View {
        VStack(spacing: 0) {
           DocumentTabBar(workspace: workspace)
                   
            if let terminal = appState.selectedTerminal {
                Group {
                    if let tree = appState.paneTrees[terminal.id] {
                        SplitTreeView(node: tree, tab: terminal, appState: appState)
                            .background(PaneFocusTracker(appState: appState, tab: terminal))
                    } else {
                        TerminalContainerRepresentable(
                            tab: terminal,
                            appState: appState
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
           BottomSheetView(directoryURL: workspace.url)
        }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    appState.splitActivePane(.horizontal)
                } label: {
                    Label("Split Right", systemImage: "rectangle.split.2x1")
                }
                .disabled(appState.selectedTerminal == nil)

                Button {
                    appState.splitActivePane(.vertical)
                } label: {
                    Label("Split Down", systemImage: "rectangle.split.1x2")
                }
                .disabled(appState.selectedTerminal == nil)
            }
            
            ToolbarSpacer(.fixed)

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
        .onChange(of: appState.scratchPadRequest) { _, newValue in
            if newValue === workspace {
                showingScratchPad = true
                appState.scratchPadRequest = nil
            }
        }
        .navigationTitle(workspace.name)
        .navigationSubtitle(workspace.directory.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
        .environment(workspace.editorPanel)
        .environment(\.showInFileTree) { url in
            workspace.inspectorState.revealInFileTree(url, relativeTo: workspace.url)
        }
        .task(id: workspace) {
            appState.selectedTerminal = workspace.terminals.first { $0.id == workspace.selectedTerminalID }
                ?? workspace.terminals.first ?? workspace.addTerminal()
        }
        .onChange(of: appState.selectedTerminal) {
            appState.selectedTerminal?.hasBellNotification = false
            workspace.selectedTerminalID = appState.selectedTerminal?.id
        }
        .alert(
            "Close Tab?",
            isPresented: Binding(
                get: { appState.terminalPendingClose != nil },
                set: { if !$0 { appState.terminalPendingClose = nil } }
            )
        ) {
            Button("Close", role: .confirm) {
                guard let terminal = appState.terminalPendingClose else { return }
                let next = workspace.terminalAfter(terminal) ?? workspace.terminalBefore(terminal)
                appState.tearDownPanes(for: terminal)
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
        .alert(
            "Close Pane?",
            isPresented: Binding(
                get: { appState.panePendingClose != nil },
                set: { if !$0 { appState.panePendingClose = nil } }
            )
        ) {
            Button("Close", role: .confirm) {
                guard let pane = appState.panePendingClose,
                      let tab = appState.selectedTerminal else { return }
                appState.closePane(pane, in: tab)
                appState.panePendingClose = nil
            }
            Button("Cancel", role: .cancel) {
                appState.panePendingClose = nil
            }
        } message: {
            if let pane = appState.panePendingClose, let name = pane.foregroundProcessName {
                Text("\"\(name)\" is still running in this pane. Are you sure you want to close it?")
            } else {
                Text("A process is still running in this pane. Are you sure you want to close it?")
            }
        }
    }
}
