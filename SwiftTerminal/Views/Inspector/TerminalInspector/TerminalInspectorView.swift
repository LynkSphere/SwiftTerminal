import SwiftUI

struct TerminalInspectorView: View {
    @Environment(AppState.self) private var appState

    private var workspace: Workspace? { appState.selectedSession?.workspace }

    @State private var selection: TerminalTab?

    var body: some View {
        if let workspace {
            VSplitView {
                List(selection: $selection) {
                    ForEach(workspace.terminals) { tab in
                        TerminalRowView(tab: tab)
                    }
                    .listRowSeparator(.hidden)
                }
                .scrollContentBackground(.hidden)
                .safeAreaBar(edge: .top) {
                    addButton
                        .controlSize(.mini)
                        .hidden()
                }
                .safeAreaBar(edge: .bottom) {
                    addButton
                }

                if workspace.unsortedTerminals.isEmpty {
                    ContentUnavailableView {
                        Label("No Terminals", systemImage: "terminal")
                    } description: {
                        Text("Add a terminal session to get started.")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    TerminalContainerRepresentable(
                        tabs: workspace.unsortedTerminals,
                        selectedTab: selection
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
                        Button("") { selection?.clearTerminal() }
                            .keyboardShortcut("k", modifiers: .command)
                            .hidden()
                    }
                }
            }
            .onAppear {
                selection = workspace.terminals.first
            }
            .onChange(of: selection) { _, newValue in
                newValue?.clearNotification()
            }
        } else {
            ContentUnavailableView("No Workspace", systemImage: "terminal", description: Text("Select a workspace to manage terminals."))
        }
    }
    
    var addButton: some View {
        Button {
            let tab = workspace?.addTerminal()
            selection = tab
        } label: {
            Label("New Terminal", systemImage: "plus")
        }
        .buttonSizing(.flexible)
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
