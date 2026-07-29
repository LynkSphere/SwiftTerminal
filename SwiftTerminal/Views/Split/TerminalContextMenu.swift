import SwiftUI

struct TerminalContextMenu: View {
    let terminal: Terminal
    let tab: Terminal
    let appState: AppState

    var body: some View {
        let isSplit = appState.isTabSplit(tab)

        Group {
            if isSplit {
                Button("Move Pane to New Tab", systemImage: "macwindow.badge.plus") {
                    appState.detachPaneToTab(terminal, from: tab)
                }

                Divider()
            }

            Button("Split Right", systemImage: "rectangle.split.2x1") {
                focusTerminal()
                appState.splitActivePane(.horizontal)
            }

            Button("Split Down", systemImage: "rectangle.split.1x2") {
                focusTerminal()
                appState.splitActivePane(.vertical)
            }

            Button("Clear Terminal", systemImage: "clear") {
                focusTerminal()
                terminal.clearTerminal()
            }

            if isSplit {
                Divider()

                Button("Close Pane", systemImage: "xmark", role: .destructive) {
                    if terminal.hasChildProcess {
                        appState.panePendingClose = terminal
                    } else {
                        appState.closePane(terminal, in: tab)
                    }
                }
            }
        }
    }

    private func focusTerminal() {
        appState.selectedTerminal = tab
        appState.focusedPaneID = terminal.id
    }
}
