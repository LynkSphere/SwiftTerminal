import SwiftUI

struct TerminalRowView: View {
    let tab: TerminalTab

    @State private var isRenaming = false
    @State private var renameText = ""

    private var subtitle: String {
        tab.shellTitle
            ?? tab.foregroundProcessName
            ?? tab.displayDirectory
    }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(tab.title)
                    .lineLimit(1)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        } icon: {
            Image(systemName: tab.hasChildProcess ? "terminal.fill" : "terminal")
        }
        .tag(tab)
        .contextMenu {
            Button("Rename...") {
                renameText = tab.title
                isRenaming = true
            }
            Divider()
            Button("Close Terminal") {
                tab.workspace?.closeTerminal(tab)
            }
        }
        .alert("Rename Terminal", isPresented: $isRenaming) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                tab.title = renameText
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
