import SwiftUI
import SwiftTerm

struct CommandEntryRow: View {
    let entry: CommandEntry
    let runner: CommandRunner
    @Environment(AppState.self) private var appState

    @State private var showEditSheet = false
    @State private var showFullOutput = false

    private var isRunning: Bool {
        runner.isRunning(entry)
    }

    private var hasOutput: Bool {
        guard let state = runner[entry] else { return false }
        return !state.output.isEmpty
    }

    var body: some View {
        DisclosureGroup {
            if let runState = runner[entry], !runState.output.isEmpty {
                outputView(runState.output)
            }
        } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(entry.name)
                            .font(.subheadline)
                            .lineLimit(1)
                        statusIndicator
                    }

                    Text(entry.command)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer()

                actionButtons
            }
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
        } else if let code = runner[entry]?.exitCode {
            Image(systemName: code == 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(code == 0 ? .green : .red)
                .font(.caption)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        Button {
            if isRunning {
                runner.stop(entry)
            } else {
                runner.run(entry, in: entry.workspace.url)
            }
        } label: {
            Image(systemName: isRunning ? "stop.fill" : "play.fill")
                .font(.caption)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Output

    private func outputView(_ output: String) -> some View {
        let truncated = output.count > 500 ? String(output.suffix(500)) : output
        return ScrollView(.vertical) {
            Text(truncated)
                .font(.system(.caption2, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxHeight: 120)
        .contentMargins(6)
        .background(.background.secondary, in: .rect(cornerRadius: 6))
        .overlay(alignment: .topTrailing) {
            if output.count > 500 {
                Button {
                    showFullOutput = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .controlSize(.small)
            }
        }
        .padding(.leading, -15)
        .sheet(isPresented: $showFullOutput) {
            fullOutputSheet(output)
        }
    }

    private func fullOutputSheet(_ output: String) -> some View {
        NavigationStack {
            ScrollView {
                Text(output)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .contentMargins(10)
            .navigationTitle(entry.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showFullOutput = false }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(output, forType: .string)
                    }
                }
            }
        }
        .frame(maxWidth: 500, maxHeight: 400)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuItems: some View {
        if isRunning {
            Button { runner.stop(entry) } label: {
                Label("Stop", systemImage: "stop.fill")
            }
        } else {
            Button {
                runner.run(entry, in: entry.workspace.url)
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
            showEditSheet = true
        } label: {
            Label("Edit", systemImage: "pencil")
        }

        Divider()

        Button(role: .destructive) {
            runner.stop(entry)
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
