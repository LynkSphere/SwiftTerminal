import SwiftUI
import SwiftTerm

struct AppCommands: Commands {
    @Bindable var appState: AppState

    var body: some Commands {
        CommandMenu("View") {
            Button {
                appState.selectedWorkspace?.selectedTab?.increaseFontSize()
            } label: {
                Label("Zoom In", systemImage: "plus.magnifyingglass")
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(appState.selectedWorkspace?.selectedTab?.localProcessTerminalView == nil)

            Button {
                appState.selectedWorkspace?.selectedTab?.decreaseFontSize()
            } label: {
                Label("Zoom Out", systemImage: "minus.magnifyingglass")
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(appState.selectedWorkspace?.selectedTab?.localProcessTerminalView == nil)

            Button {
                appState.selectedWorkspace?.selectedTab?.resetFontSize()
            } label: {
                Label("Actual Size", systemImage: "1.magnifyingglass")
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(appState.selectedWorkspace?.selectedTab?.localProcessTerminalView == nil)
        }

        CommandMenu("Editor") {
            Button("Toggle Editor Panel") {
                appState.panelToggleToken = UUID()
            }
            .keyboardShortcut("j", modifiers: .command)
        }

        CommandMenu("Inspector") {
            Button("Files") {
                appState.showingInspector = true
                appState.selectedInspectorTab = .files
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Git") {
                appState.showingInspector = true
                appState.selectedInspectorTab = .git
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("Search") {
                appState.showingInspector = true
                appState.selectedInspectorTab = .search
            }
            .keyboardShortcut("3", modifiers: .command)

            Divider()

            Button("Find in Files") {
                appState.showingInspector = true
                appState.selectedInspectorTab = .search
                appState.searchFocusToken = UUID()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
        }

        CommandMenu("Terminal") {
            Button {
                guard let terminalView = appState.selectedWorkspace?.selectedTab?.localProcessTerminalView else { return }
                let terminal = terminalView.getTerminal()
                terminal.resetToInitialState()
                terminalView.send(txt: "\u{0C}")
            } label: {
                Label("Clear Terminal", systemImage: "clear")
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(appState.selectedWorkspace?.selectedTab?.localProcessTerminalView == nil)
        }

        CommandMenu("Tabs") {
            Button {
                withAnimation {
                    _ = appState.selectedWorkspace?.addTab(
                        currentDirectory: appState.selectedWorkspace?.selectedTab?.liveCurrentDirectory
                    )
                }
            } label: {
                Label("New Tab", systemImage: "plus.square")
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(appState.selectedWorkspace == nil)

            Button {
                withAnimation {
                    _ = appState.selectedWorkspace?.addTab(
                        currentDirectory: appState.selectedWorkspace?.directory
                    )
                }
            } label: {
                Label("New Tab in Workspace Directory", systemImage: "plus.square.on.square")
            }
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(appState.selectedWorkspace == nil)

            Button {
                guard let tab = appState.selectedWorkspace?.selectedTab else { return }
                if tab.hasChildProcess {
                    appState.tabToClose = tab
                    appState.showCloseConfirmation = true
                } else {
                    appState.selectedWorkspace?.closeTab(tab)
                }
            } label: {
                Label("Close Tab", systemImage: "xmark.square")
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled((appState.selectedWorkspace?.tabs.count ?? 0) < 2)

            Divider()

            Button {
                appState.selectedWorkspace?.selectPreviousTab()
            } label: {
                Label("Select Previous Tab", systemImage: "chevron.left.square")
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])
            .disabled((appState.selectedWorkspace?.tabs.count ?? 0) < 2)

            Button {
                appState.selectedWorkspace?.selectNextTab()
            } label: {
                Label("Select Next Tab", systemImage: "chevron.right.square")
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])
            .disabled((appState.selectedWorkspace?.tabs.count ?? 0) < 2)
        }
    }
}
