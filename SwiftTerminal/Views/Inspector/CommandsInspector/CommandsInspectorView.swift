import SwiftUI

struct CommandsInspectorView: View {
    let workspace: Workspace

    @State private var selection: CommandEntry?
    @State private var showAddSheet = false

    var body: some View {
        VSplitView {
            commandList
            outputPanel
                .frame(minHeight: 200)
                .frame(maxWidth: .infinity)
        }
        .safeAreaBar(edge: .top) {
            HStack {
                Text("Commands")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .padding(.top, 7)
        }
        .sheet(isPresented: $showAddSheet) {
            CommandEntrySheet(workspace: workspace)
        }
    }

    private var commandList: some View {
        List(workspace.commands, selection: $selection) { entry in
            CommandEntryRow(entry: entry, selection: $selection)
                .tag(entry)
                .listRowSeparator(.hidden)
        }
        .safeAreaInset(edge: .top) {
            Color.clear.frame(height: 50)
        }
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private var outputPanel: some View {
        if let entry = selection {
            let runner = entry.runner
            if runner.output.isEmpty && !runner.isRunning {
                Text("No output")
                    .foregroundStyle(.tertiary)
                    .font(.callout)
            } else {
                CommandOutputView(text: runner.output)
            }
        } else {
            Color.clear
        }
    }
}
