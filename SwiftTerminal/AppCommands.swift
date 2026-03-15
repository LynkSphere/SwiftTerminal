import SwiftUI
import SwiftTerm

struct AppCommands: Commands {
    @Bindable var appState: AppState

    var body: some Commands {
        CommandMenu("Terminal") {
            Button("Clear Terminal") {
                guard let terminalView = appState.selectedWorkspace?.selectedTab?.localProcessTerminalView else { return }
                let terminal = terminalView.getTerminal()
                terminal.resetToInitialState()
                // Send Ctrl+L to the shell to redraw the prompt
                terminalView.send(txt: "\u{0C}")
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(appState.selectedWorkspace?.selectedTab?.localProcessTerminalView == nil)
        }

        CommandMenu("Tabs") {
            Button("New Tab") {
                withAnimation {
                    _ = appState.selectedWorkspace?.addTabFromSelectedDirectory()
                }
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(appState.selectedWorkspace == nil)

            Button("Close Tab") {
                appState.closeSelectedTabWithConfirmation()
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled((appState.selectedWorkspace?.tabs.count ?? 0) < 2)

            Divider()

            Button("Select Previous Tab") {
                appState.selectedWorkspace?.selectPreviousTab()
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])
            .disabled((appState.selectedWorkspace?.tabs.count ?? 0) < 2)

            Button("Select Next Tab") {
                appState.selectedWorkspace?.selectNextTab()
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])
            .disabled((appState.selectedWorkspace?.tabs.count ?? 0) < 2)
        }
    }
}
