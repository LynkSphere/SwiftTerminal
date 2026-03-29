import SwiftUI

struct AppCommands: Commands {
    @Bindable var appState: AppState
    @FocusedValue(\.editorPanel) private var editorPanel
    @AppStorage("showHiddenFiles") var showHiddenFiles = false

    var body: some Commands {
        CommandGroup(replacing: .toolbar) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    editorPanel?.toggle()
                }
            } label: {
                Label("Toggle Editor Panel", systemImage: "rectangle.bottomhalf.inset.filled")
            }
            .keyboardShortcut("j", modifiers: .command)

            Divider()

            Button {
                showHiddenFiles.toggle()
            } label: {
                Label(
                    showHiddenFiles ? "Hide Hidden Files" : "Show Hidden Files",
                    systemImage: showHiddenFiles ? "eye.slash" : "eye"
                )
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])
        }

        CommandMenu("Inspector") {
            Button {
                appState.showingInspector = true
                appState.selectedInspectorTab = .files
            } label: {
                Label("Files Navigator", systemImage: "folder")
            }
            .keyboardShortcut("1", modifiers: .command)

            Button {
                appState.showingInspector = true
                appState.selectedInspectorTab = .git
            } label: {
                Label("Git Navigator", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
            }
            .keyboardShortcut("2", modifiers: .command)

            Button {
                appState.showingInspector = true
                appState.selectedInspectorTab = .search
            } label: {
                Label("Search Navigator", systemImage: "magnifyingglass")
            }
            .keyboardShortcut("3", modifiers: .command)

            Button {
                appState.showingInspector = true
                appState.selectedInspectorTab = .terminal
            } label: {
                Label("Terminal", systemImage: "terminal")
            }
            .keyboardShortcut("4", modifiers: .command)

            Divider()

            Button {
                appState.showingInspector = true
                appState.selectedInspectorTab = .search
            } label: {
                Label("Find in Files", systemImage: "doc.text.magnifyingglass")
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
        }

        CommandGroup(after: .textEditing) {
            Button("Find…") {
                let item = NSMenuItem()
                item.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
                NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: item)
            }
            .keyboardShortcut("f", modifiers: .command)

            Button("Find and Replace…") {
                let item = NSMenuItem()
                item.tag = Int(NSFindPanelAction.setFindString.rawValue)
                NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: item)
            }
            .keyboardShortcut("f", modifiers: [.command, .option])
        }
    }
}
