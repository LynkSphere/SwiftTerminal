import SwiftUI

@Observable
final class Workspace: Identifiable, Hashable, Codable {
    var id: UUID
    var name: String

    var directory: String
    var projectTypeRaw: String
    var scratchPad: String
    var isArchived: Bool = false
    private(set) var customIconFilename: String?

    private(set) var terminals: [Terminal]
    private(set) var commands: [Terminal]

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

    // MARK: - Custom Icon

    static func iconsDirectory() -> URL {
        let fm = FileManager.default
        let appSupport = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = appSupport
            .appendingPathComponent("SwiftTerminal", isDirectory: true)
            .appendingPathComponent("WorkspaceIcons", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var customIconURL: URL? {
        guard let name = customIconFilename, !name.isEmpty else { return nil }
        return Self.iconsDirectory().appendingPathComponent(name)
    }

    func setCustomIcon(from sourceURL: URL) throws {
        let fm = FileManager.default
        let dir = Self.iconsDirectory()
        let allowed: Set<String> = ["icns", "png", "jpg", "jpeg"]
        let ext = sourceURL.pathExtension.lowercased()
        let safeExt = allowed.contains(ext) ? ext : "png"
        let filename = "\(id.uuidString).\(safeExt)"
        let dest = dir.appendingPathComponent(filename)

        if let prior = customIconFilename {
            try? fm.removeItem(at: dir.appendingPathComponent(prior))
        }
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.copyItem(at: sourceURL, to: dest)
        customIconFilename = filename
        store?.scheduleSave()
    }

    func clearCustomIcon() {
        if let name = customIconFilename {
            let url = Self.iconsDirectory().appendingPathComponent(name)
            try? FileManager.default.removeItem(at: url)
        }
        customIconFilename = nil
        store?.scheduleSave()
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
        case id, name, directory, projectTypeRaw, scratchPad, isArchived
        case customIconFilename
        case terminals, commands
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.directory = try c.decode(String.self, forKey: .directory)
        let rawProjectType = try c.decodeIfPresent(String.self, forKey: .projectTypeRaw) ?? ProjectType.unknown.rawValue
        // Legacy: "xcode" was folded into "swiftPackage" (now displayed as "Swift")
        // since Xcode projects are just one flavor of Swift project.
        self.projectTypeRaw = rawProjectType == "xcode" ? ProjectType.swiftPackage.rawValue : rawProjectType
        self.scratchPad = try c.decodeIfPresent(String.self, forKey: .scratchPad) ?? ""
        self.isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        self.customIconFilename = try c.decodeIfPresent(String.self, forKey: .customIconFilename)
        self.terminals = try c.decodeIfPresent([Terminal].self, forKey: .terminals) ?? []
        self.commands = try c.decodeIfPresent([Terminal].self, forKey: .commands) ?? []
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
        try c.encode(isArchived, forKey: .isArchived)
        try c.encodeIfPresent(customIconFilename, forKey: .customIconFilename)
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

    /// A terminal that lives inside a split layout, not as a tab (not appended to
    /// `terminals`). Owned by the `AppState` pane tree.
    func makeDetachedPane(currentDirectory: String?) -> Terminal {
        Terminal(workspace: self, currentDirectory: currentDirectory ?? directory)
    }

    /// Swaps a tab's representative terminal in place, preserving its position,
    /// when a surviving split pane is promoted to be the tab.
    func replaceTerminal(_ old: Terminal, with new: Terminal) {
        guard let idx = terminals.firstIndex(where: { $0 === old }) else { return }
        new.workspace = self
        terminals[idx] = new
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
    func addCommand(title: String = "Terminal", runScript: String? = nil) -> Terminal {
        let entry = Terminal(workspace: self, title: title, runScript: runScript)
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

    func moveCommands(from source: IndexSet, to destination: Int) {
        commands.move(fromOffsets: source, toOffset: destination)
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
        terminals.contains { $0.localProcessTerminalView != nil }
            || commands.contains { $0.localProcessTerminalView != nil }
    }

    var hasActiveChildProcess: Bool {
        terminals.contains { $0.hasChildProcess }
            || commands.contains { $0.hasChildProcess }
    }

    func killAllRunningTerminals() {
        for t in terminals { t.terminate() }
        for cmd in commands { cmd.terminate() }
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
}
