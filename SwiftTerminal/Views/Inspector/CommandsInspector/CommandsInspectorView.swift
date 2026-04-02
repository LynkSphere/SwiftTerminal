import SwiftUI

struct CommandsInspectorView: View {
    let workspace: Workspace
    @Bindable var state: CommandsInspectorState

    var body: some View {
        List {
            ForEach(workspace.commands) { entry in
                CommandEntryRow(entry: entry, runner: state.runner)
            }
            .onMove { from, to in
                reorder(from: from, to: to)
            }
            .listRowSeparator(.hidden)
        }
        .scrollContentBackground(.hidden)
        .overlay {
            if workspace.commands.isEmpty {
                ContentUnavailableView {
                    Label("No Commands", systemImage: "terminal")
                } description: {
                    Text("Add commands like build, run, or test.")
                } actions: {
                    Button("Add Command") {
                        state.showAddSheet = true
                    }
                }
            }
        }
        .safeAreaBar(edge: .top) {
            HStack {
                Text("Commands")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    state.showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .padding(.top, 7)
        }
        .sheet(isPresented: $state.showAddSheet) {
            CommandEntrySheet(workspace: workspace)
        }
    }

    private func reorder(from source: IndexSet, to destination: Int) {
        var ordered = workspace.commands
        ordered.move(fromOffsets: source, toOffset: destination)
        for (i, entry) in ordered.enumerated() {
            entry.sortOrder = i
        }
    }
}
