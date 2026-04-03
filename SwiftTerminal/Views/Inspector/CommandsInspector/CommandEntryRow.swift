import SwiftUI
import SwiftTerm

struct CommandEntryRow: View {
    let entry: CommandEntry
    @Binding var selection: CommandEntry?
    @Environment(AppState.self) private var appState

    @State private var showEditSheet = false

    private var runner: CommandRunner { entry.runner }
    private var isRunning: Bool { runner.isRunning }

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .font(.callout)
                        .lineLimit(1)
                    statusIndicator
                }

                Text(entry.command)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            actionButtons
        }
        .contextMenu {
            contextMenuItems
        }
        .sheet(isPresented: $showEditSheet) {
            CommandEntrySheet(workspace: entry.workspace, entry: entry)
        }
    }

    // MARK: - Status Indicator

    @ViewBuilder
    private var statusIndicator: some View {
        if isRunning {
            ProgressView()
                .controlSize(.mini)
                .frame(width: 14, height: 14)
        } else if let code = runner.exitCode {
            Image(systemName: code == 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(code == 0 ? .green : .red)
                .font(.caption)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        Button {
            if isRunning {
                runner.stop()
            } else {
                entry.run()
                selection = entry
            }
        } label: {
            Image(systemName: isRunning ? "stop.fill" : "play.fill")
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuItems: some View {
        if isRunning {
            Button { runner.stop() } label: {
                Label("Stop", systemImage: "stop.fill")
            }
        } else {
            Button {
                entry.run()
            } label: {
                Label("Run", systemImage: "play.fill")
            }

            Button {
                runInNewTerminal()
            } label: {
                Label("Run in Terminal", systemImage: "terminal")
            }
        }

        Divider()

        Button {
            entry.workspace.setDefaultCommand(entry)
        } label: {
            Label("Set as Run Command", systemImage: entry.isDefault ? "checkmark" : "play.circle")
        }
        .disabled(entry.isDefault)

        Button {
            showEditSheet = true
        } label: {
            Label("Edit", systemImage: "pencil")
        }

        Divider()

        Button(role: .destructive) {
            runner.stop()
            entry.workspace.removeCommand(entry)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func runInNewTerminal() {
        let workspace = entry.workspace
        let terminal = workspace.addTerminal()
        appState.selectedTerminal = terminal
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            if let tv = terminal.localProcessTerminalView {
                tv.send(txt: entry.command + "\n")
            }
        }
    }
}
