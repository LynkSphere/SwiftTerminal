import SwiftUI

struct TerminalRow: View {
    @Environment(AppState.self) private var appState

    let terminal: Terminal

    @State private var isRenaming = false
    @State private var renameText = ""
    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: terminal.hasChildProcess ? "terminal.fill" : "terminal")

            if isRenaming {
                TextField("Terminal Name", text: $renameText)
                    .textFieldStyle(.plain)
                    .focused($isNameFieldFocused)
                    .onSubmit { commitRename() }
                    .onExitCommand { isRenaming = false }
                    .onAppear {
                        renameText = terminal.title
                        isNameFieldFocused = true
                    }
            } else {
                Text(terminal.title)
                    .lineLimit(1)
            }
        }
        .badge(terminal.hasBellNotification ? "" : nil)
        .badgeProminence(.increased)
        .contextMenu {
            RenameButton()

            Divider()

            Button("Close Terminal", systemImage: "trash", role: .destructive) {
                closeTerminal()
            }
        }
        .renameAction {
            isRenaming = true
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                closeTerminal()
            } label: {
                Label("Close", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
        }
    }

    private func commitRename() {
        isRenaming = false
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != terminal.title else { return }
        terminal.title = trimmed
    }

    private func closeTerminal() {
        if appState.selectedTerminal == terminal {
            appState.selectedTerminal = nil
        }
        terminal.workspace?.closeTerminal(terminal)
    }
}
