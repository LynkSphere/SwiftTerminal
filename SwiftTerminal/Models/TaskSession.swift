import Foundation
import Observation

@MainActor
@Observable
final class TaskSession: Identifiable {
    let id: String
    var thread: AgentThread
    let workspace: Workspace
    private(set) var terminal: Terminal

    init(thread: AgentThread, workspace: Workspace, command: String) {
        id = thread.id
        self.thread = thread
        self.workspace = workspace
        terminal = Terminal(workspace: workspace, title: thread.title, currentDirectory: thread.directory)
        terminal.pendingStartupCommand = "exec " + command
    }

    func restart(command: String) {
        terminal.terminate()
        terminal = Terminal(workspace: workspace, title: thread.title, currentDirectory: thread.directory)
        terminal.pendingStartupCommand = "exec " + command
    }
}
