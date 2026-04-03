import Foundation
import SwiftData

@Model
final class Workspace {
    var id = UUID()
    var name: String = ""
    var sortOrder: Int = 0
    
    var directory: String = ""
    var projectTypeRaw: String = ProjectType.unknown.rawValue
    var scratchPad: String = ""

    @Transient var inspectorState = InspectorViewState()
    @Transient var editorPanel = EditorPanel()

    var url: URL {
        URL(fileURLWithPath: directory)
    }

    var projectType: ProjectType {
        get { ProjectType(rawValue: projectTypeRaw) ?? .unknown }
        set { projectTypeRaw = newValue.rawValue }
    }

    func detectProjectType() {
        projectType = ProjectType.detect(at: url)
    }

    @Relationship(deleteRule: .cascade, inverse: \Terminal.workspace)
    var unsortedTerminals: [Terminal] = []
    var terminals: [Terminal] {
        unsortedTerminals.sorted { $0.sortOrder < $1.sortOrder }
    }

    @Relationship(deleteRule: .cascade, inverse: \CommandEntry.workspace)
    var unsortedCommands: [CommandEntry] = []
    var commands: [CommandEntry] {
        unsortedCommands.sorted { $0.sortOrder < $1.sortOrder }
    }

    init(name: String, directory: String, sortOrder: Int = 0) {
        self.name = name
        self.directory = directory
        self.sortOrder = sortOrder
    }
    
    // MARK: - Terminal Management

    @discardableResult
    func addTerminal(currentDirectory: String? = nil, after current: Terminal? = nil) -> Terminal {
        let ordered = terminals
        let insertIndex: Int
        if let current, let idx = ordered.firstIndex(where: { $0 === current }) {
            insertIndex = idx + 1
        } else {
            insertIndex = ordered.count
        }

        for t in ordered where t.sortOrder >= insertIndex {
            t.sortOrder += 1
        }

        let tab = Terminal(workspace: self, currentDirectory: currentDirectory ?? directory, sortOrder: insertIndex)
        unsortedTerminals.append(tab)
        return tab
    }

    func closeTerminal(_ tab: Terminal) {
        tab.terminate()
        unsortedTerminals.removeAll { $0.id == tab.id }
        tab.modelContext?.delete(tab)
    }

    func terminalBefore(_ terminal: Terminal) -> Terminal? {
        let ordered = terminals
        guard let idx = ordered.firstIndex(where: { $0 === terminal }), idx > 0 else { return nil }
        return ordered[idx - 1]
    }

    func terminalAfter(_ terminal: Terminal) -> Terminal? {
        let ordered = terminals
        guard let idx = ordered.firstIndex(where: { $0 === terminal }), idx + 1 < ordered.count else { return nil }
        return ordered[idx + 1]
    }

    // MARK: - Command Management

    @discardableResult
    func addCommand(name: String, command: String) -> CommandEntry {
        let entry = CommandEntry(
            workspace: self,
            name: name,
            command: command,
            sortOrder: unsortedCommands.count
        )
        unsortedCommands.append(entry)
        return entry
    }

    var defaultCommand: CommandEntry? {
        commands.first { $0.isDefault }
    }

    func setDefaultCommand(_ entry: CommandEntry) {
        for cmd in unsortedCommands {
            cmd.isDefault = cmd.id == entry.id
        }
    }

    func removeCommand(_ entry: CommandEntry) {
        CommandRunner.remove(for: entry.id)
        unsortedCommands.removeAll { $0.id == entry.id }
        entry.modelContext?.delete(entry)
    }
}
