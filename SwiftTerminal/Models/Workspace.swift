import Foundation
import Observation

@Observable
final class Workspace: Identifiable, Hashable, Codable {
    var id: UUID
    var name: String

    var directory: String
    var projectTypeRaw: String
    var scratchPad: String

    private(set) var terminals: [Terminal]
    private(set) var commands: [CommandEntry]

    @ObservationIgnored
    weak var store: WorkspaceStore?

    @ObservationIgnored
    var inspectorState = InspectorViewState()

    @ObservationIgnored
    var editorPanel = EditorPanel()

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

    init(name: String, directory: String) {
        self.id = UUID()
        self.name = name
        self.directory = directory
        self.projectTypeRaw = ProjectType.unknown.rawValue
        self.scratchPad = ""
        self.terminals = []
        self.commands = []
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, name, directory, projectTypeRaw, scratchPad
        case terminals, commands
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.directory = try c.decode(String.self, forKey: .directory)
        self.projectTypeRaw = try c.decodeIfPresent(String.self, forKey: .projectTypeRaw) ?? ProjectType.unknown.rawValue
        self.scratchPad = try c.decodeIfPresent(String.self, forKey: .scratchPad) ?? ""
        self.terminals = try c.decodeIfPresent([Terminal].self, forKey: .terminals) ?? []
        self.commands = try c.decodeIfPresent([CommandEntry].self, forKey: .commands) ?? []
        for t in terminals { t.workspace = self }
        for cmd in commands { cmd.workspace = self }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(directory, forKey: .directory)
        try c.encode(projectTypeRaw, forKey: .projectTypeRaw)
        try c.encode(scratchPad, forKey: .scratchPad)
        try c.encode(terminals, forKey: .terminals)
        try c.encode(commands, forKey: .commands)
    }

    // MARK: - Hashable

    static func == (lhs: Workspace, rhs: Workspace) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - Terminal Management

    @discardableResult
    func addTerminal(currentDirectory: String? = nil, after current: Terminal? = nil) -> Terminal {
        let tab = Terminal(workspace: self, currentDirectory: currentDirectory ?? directory)
        if let current, let idx = terminals.firstIndex(where: { $0 === current }) {
            terminals.insert(tab, at: idx + 1)
        } else {
            terminals.append(tab)
        }
        store?.scheduleSave()
        return tab
    }

    func closeTerminal(_ tab: Terminal) {
        tab.terminate()
        terminals.removeAll { $0.id == tab.id }
        store?.scheduleSave()
    }

    func reorderTerminals(_ newOrder: [Terminal]) {
        terminals = newOrder
        store?.scheduleSave()
    }

    func terminalBefore(_ terminal: Terminal) -> Terminal? {
        guard let idx = terminals.firstIndex(where: { $0 === terminal }), idx > 0 else { return nil }
        return terminals[idx - 1]
    }

    func terminalAfter(_ terminal: Terminal) -> Terminal? {
        guard let idx = terminals.firstIndex(where: { $0 === terminal }), idx + 1 < terminals.count else { return nil }
        return terminals[idx + 1]
    }

    // MARK: - Command Management

    @discardableResult
    func addCommand(name: String, command: String) -> CommandEntry {
        let entry = CommandEntry(workspace: self, name: name, command: command)
        commands.append(entry)
        store?.scheduleSave()
        return entry
    }

    var defaultCommand: CommandEntry? {
        commands.first { $0.isDefault }
    }

    func setDefaultCommand(_ entry: CommandEntry) {
        for cmd in commands {
            cmd.isDefault = cmd.id == entry.id
        }
        store?.scheduleSave()
    }

    func removeCommand(_ entry: CommandEntry) {
        CommandRunner.remove(for: entry.id)
        commands.removeAll { $0.id == entry.id }
        store?.scheduleSave()
    }
}
