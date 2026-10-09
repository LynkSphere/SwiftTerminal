import SwiftUI

struct PaneContextMenu: View {
    let pane: Pane
    let tab: WorkspaceTab
    let appState: AppState

    var body: some View {
        let isSplit = tab.isSplit

        Group {
            if isSplit {
                Button("Move Pane to New Tab", systemImage: "macwindow.badge.plus") {
                    appState.detachPaneToTab(pane, from: tab)
                }

                Divider()
            }

            Button("Split Right", systemImage: "rectangle.split.2x1") {
                focusPane()
                appState.splitActivePane(.horizontal)
            }

            Button("Split Down", systemImage: "rectangle.split.1x2") {
                focusPane()
                appState.splitActivePane(.vertical)
            }

            if let terminal = pane.terminal {
                Button("Clear Terminal", systemImage: "clear") {
                    focusPane()
                    terminal.clearTerminal()
                }
            }

            if isSplit {
                Divider()

                Button("Close Pane", systemImage: "xmark", role: .destructive) {
                    appState.requestClosePane(pane, in: tab)
                }
            }
        }
    }

    private func focusPane() {
        appState.selectedTab = tab
        tab.focus(pane)
    }
}
