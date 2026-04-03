import Foundation
import SwiftData

@Model
final class CommandEntry {
    var id = UUID()
    var name: String = ""
    var command: String = ""
    var sortOrder: Int = 0
    var isDefault: Bool = false
    var workspace: Workspace

    var runner: CommandRunner {
        CommandRunner.runner(for: id)
    }

    init(workspace: Workspace, name: String, command: String, sortOrder: Int = 0) {
        self.workspace = workspace
        self.name = name
        self.command = command
        self.sortOrder = sortOrder
    }

    func run() {
        runner.run(command: command, in: workspace.url)
    }
}
