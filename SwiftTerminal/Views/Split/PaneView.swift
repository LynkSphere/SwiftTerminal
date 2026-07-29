import SwiftUI

/// A single terminal pane: the terminal view plus a focus border.
struct PaneView: View {
    let terminal: Terminal
    let tab: Terminal
    let appState: AppState

    var body: some View {
        let isActive = appState.isPaneActive(terminal, in: tab)
        TerminalContainerRepresentable(tab: terminal, appState: appState, isActive: isActive)
            .contextMenu {
                TerminalContextMenu(terminal: terminal, tab: tab, appState: appState)
            }
            .overlay {
                Rectangle()
                    .strokeBorder(isActive ? Color.accentColor.opacity(0.7) : Color.clear)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityAction(named: "Move Pane to New Tab") {
                appState.detachPaneToTab(terminal, from: tab)
            }
    }
}
