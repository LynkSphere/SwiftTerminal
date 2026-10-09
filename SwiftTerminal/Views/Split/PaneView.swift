import SwiftUI

struct PaneView: View {
    let pane: Pane
    let tab: WorkspaceTab
    let appState: AppState

    var body: some View {
        let isActive = tab.focusedPane === pane

        Group {
            switch pane.content {
            case .terminal(let terminal):
                TerminalContainerRepresentable(tab: terminal, appState: appState, isActive: isActive)
            }
        }
        .background {
            PaneFocusRegion(pane: pane)
        }
        .contextMenu {
            PaneContextMenu(pane: pane, tab: tab, appState: appState)
        }
        .overlay {
            Rectangle()
                .strokeBorder(isActive && tab.isSplit ? Color.accentColor.opacity(0.7) : Color.clear)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityAction(named: "Move Pane to New Tab") {
            appState.detachPaneToTab(pane, from: tab)
        }
    }
}
