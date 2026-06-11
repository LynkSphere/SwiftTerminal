import SwiftUI

/// A single terminal pane: the terminal view plus a focus border.
struct PaneView: View {
    let terminal: Terminal
    let tab: Terminal
    let appState: AppState

    var body: some View {
        let isActive = appState.isPaneActive(terminal, in: tab)
        TerminalContainerRepresentable(tab: terminal, appState: appState, isActive: isActive)
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isActive ? Color.accentColor.opacity(0.7) : Color.clear, lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
