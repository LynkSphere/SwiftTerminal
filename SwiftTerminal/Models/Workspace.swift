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
    private(set) var commands: [Terminal]
    private(set) var chats: [Chat]

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
        self.chats = []
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, name, directory, projectTypeRaw, scratchPad
        case terminals, commands, chats
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.directory = try c.decode(String.self, forKey: .directory)
        self.projectTypeRaw = try c.decodeIfPresent(String.self, forKey: .projectTypeRaw) ?? ProjectType.unknown.rawValue
        self.scratchPad = try c.decodeIfPresent(String.self, forKey: .scratchPad) ?? ""
        self.terminals = try c.decodeIfPresent([Terminal].self, forKey: .terminals) ?? []
        self.commands = try c.decodeIfPresent([Terminal].self, forKey: .commands) ?? []
        self.chats = try c.decodeIfPresent([Chat].self, forKey: .chats) ?? []
        for t in terminals { t.workspace = self }
        for cmd in commands { cmd.workspace = self }
        for chat in chats { chat.workspace = self }
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
        try c.encode(chats, forKey: .chats)
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
    func addCommand(title: String = "Claude", runScript: String? = nil) -> Terminal {
        let entry = Terminal(workspace: self, title: title, currentDirectory: directory, runScript: runScript)
        commands.append(entry)
        store?.scheduleSave()
        return entry
    }

    var defaultCommand: Terminal? {
        commands.first { $0.isDefault }
    }

    func setDefaultCommand(_ entry: Terminal) {
        for cmd in commands {
            cmd.isDefault = cmd.id == entry.id
        }
        store?.scheduleSave()
    }

    func removeCommand(_ entry: Terminal) {
        if inspectorState.selectedCommand?.id == entry.id {
            inspectorState.selectedCommand = nil
        }
        entry.terminate()
        commands.removeAll { $0.id == entry.id }
        store?.scheduleSave()
    }

    /// Selects the command in the inspector (which triggers shell spawn via the
    /// inline terminal view) and then sends its `runScript` after a short delay
    /// to ensure the view has rendered.
    func runCommand(_ entry: Terminal) {
        inspectorState.selectedTab = .commands
        inspectorState.selectedCommand = entry
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            entry.run()
        }
    }

    // MARK: - Session Management

    func appendChat(_ chat: Chat) {
        chat.workspace = self
        chats.append(chat)
        store?.scheduleSave()
    }

    @discardableResult
    func addSession(title: String = "New Chat", provider: AgentProvider = .codex) -> Chat {
        let tracked = Chat(
            title: title,
            provider: provider,
            sortOrder: chats.count
        )
        tracked.workspace = self
        chats.append(tracked)
        store?.scheduleSave()
        return tracked
    }

    func removeSession(_ session: Chat) {
        session.disconnect()
        chats.removeAll { $0.id == session.id }
        store?.scheduleSave()
    }
}
