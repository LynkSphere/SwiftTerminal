import Foundation
import Observation

@Observable
final class Workspace: Identifiable, Hashable, Codable {
    var id: UUID
    var name: String

    var directory: String
    var projectTypeRaw: String
    var scratchPad: String

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
        self.commands = []
        self.chats = []
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, name, directory, projectTypeRaw, scratchPad
        case commands, chats
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.directory = try c.decode(String.self, forKey: .directory)
        self.projectTypeRaw = try c.decodeIfPresent(String.self, forKey: .projectTypeRaw) ?? ProjectType.unknown.rawValue
        self.scratchPad = try c.decodeIfPresent(String.self, forKey: .scratchPad) ?? ""
        self.commands = try c.decodeIfPresent([Terminal].self, forKey: .commands) ?? []
        self.chats = try c.decodeIfPresent([Chat].self, forKey: .chats) ?? []
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

    var hasRunningTerminals: Bool {
        commands.contains { $0.localProcessTerminalView != nil }
    }

    func killAllRunningTerminals() {
        for cmd in commands {
            cmd.terminate()
        }
    }

    func removeAllCommands() {
        inspectorState.selectedCommand = nil
        for cmd in commands {
            cmd.terminate()
        }
        commands.removeAll()
        store?.scheduleSave()
    }

    /// Selects the command in the inspector and sends its `runScript`.
    /// If the terminal view hasn't been created yet, switches to the Commands
    /// tab so the view renders and spawns the shell; otherwise runs in place
    /// without disturbing the user's current tab.
    func runCommand(_ entry: Terminal) {
        inspectorState.selectedCommand = entry
        let needsSpawn = entry.localProcessTerminalView == nil
        if needsSpawn {
            inspectorState.selectedTab = .commands
        }
        Task { @MainActor in
            if needsSpawn {
                try? await Task.sleep(for: .milliseconds(300))
            }
            entry.run()
        }
    }

    // MARK: - Chat Management

    func appendChat(_ chat: Chat) {
        chat.workspace = self
        chats.append(chat)
        store?.scheduleSave()
    }

    @discardableResult
    func addChat(title: String = "New Chat", provider: AgentProvider = .codex, permissionMode: PermissionMode = .bypassPermissions) -> Chat {
        let chat = Chat(
            title: title,
            provider: provider,
            permissionMode: permissionMode,
            sortOrder: chats.count
        )
        chat.workspace = self
        chats.append(chat)
        store?.scheduleSave()
        return chat
    }

    func removeChat(_ chat: Chat) {
        chat.disconnect()
        chats.removeAll { $0.id == chat.id }
        store?.scheduleSave()
    }

    var hasActiveChats: Bool {
        chats.contains { $0.isActive }
    }

    var connectedChatCount: Int {
        chats.lazy.filter { !$0.isArchived && $0.isActive }.count
    }

    func disconnectAllActiveChats() {
        for chat in chats where chat.isActive {
            chat.disconnect()
        }
    }
}
