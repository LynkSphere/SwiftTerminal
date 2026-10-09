import SwiftUI

struct WorkspaceDetailView: View {
    let workspace: Workspace
    @Environment(AppState.self) private var appState
    @State private var showingScratchPad = false

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceTabBar(workspace: workspace)
                .zIndex(1)

            if let tab = appState.selectedTab {
                SplitTreeView(node: tab.layout, tab: tab, appState: appState)
                    .background(PaneFocusTracker(tab: tab))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
           BottomSheetView(directoryURL: workspace.url)
        }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    showingScratchPad = true
                } label: {
                    Label("Scratch Pad", systemImage: "note.text")
                }
                .keyboardShortcut(".")
            }

            ToolbarItem(placement: .automatic) {
                ControlGroup {
                    Button("Split Right", systemImage: "rectangle.split.2x1") {
                        appState.splitActivePane(.horizontal)
                    }
                    .disabled(appState.selectedTab == nil)

                    Button("Split Down", systemImage: "rectangle.split.1x2") {
                        appState.splitActivePane(.vertical)
                    }
                    .disabled(appState.selectedTab == nil)
                }
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
            appState.selectedTab = workspace.tabs.first { $0.id == workspace.selectedTabID }
                ?? workspace.tabs.first ?? workspace.addTerminal()
        }
        .onChange(of: appState.selectedTab) {
            appState.selectedPane?.terminal?.hasBellNotification = false
            workspace.selectedTabID = appState.selectedTab?.id
        }
        .alert(
            "Close Tab?",
            isPresented: Binding(
                get: { appState.tabPendingClose != nil },
                set: { if !$0 { appState.tabPendingClose = nil } }
            )
        ) {
            Button("Close", role: .confirm) {
                guard let tab = appState.tabPendingClose else { return }
                appState.closeTab(tab)
                appState.tabPendingClose = nil
            }
            Button("Cancel", role: .cancel) {
                appState.tabPendingClose = nil
            }
        } message: {
            if let tab = appState.tabPendingClose, let name = tab.panes.compactMap({ $0.terminal?.foregroundProcessName }).first {
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
                      let tab = pane.workspace?.tab(containing: pane) else { return }
                appState.closePane(pane, in: tab)
                appState.panePendingClose = nil
            }
            Button("Cancel", role: .cancel) {
                appState.panePendingClose = nil
            }
        } message: {
            if let pane = appState.panePendingClose, let name = pane.terminal?.foregroundProcessName {
                Text("\"\(name)\" is still running in this pane. Are you sure you want to close it?")
            } else {
                Text("A process is still running in this pane. Are you sure you want to close it?")
            }
        }
    }
}
