import AppKit
import Observation
import SwiftTerm

@Observable
final class Terminal: Identifiable, Hashable, Codable {
    var id: UUID
    var title: String
    var currentDirectory: String?

    @ObservationIgnored
    weak var workspace: Workspace?

    /// Not encoded; reset per launch.
    @ObservationIgnored
    var hasBellNotification = false

    var localProcessTerminalView: LocalProcessTerminalView? {
        get { TerminalProcessRegistry.view(for: id) }
        set {
            if let newValue {
                TerminalProcessRegistry.register(newValue, for: id)
            } else {
                TerminalProcessRegistry.remove(for: id)
            }
        }
    }

    init(workspace: Workspace, title: String = "Terminal", currentDirectory: String? = nil) {
        self.id = UUID()
        self.workspace = workspace
        self.title = title
        self.currentDirectory = currentDirectory
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, title, currentDirectory
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Terminal"
        self.currentDirectory = try c.decodeIfPresent(String.self, forKey: .currentDirectory)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(currentDirectory, forKey: .currentDirectory)
    }

    // MARK: - Hashable

    static func == (lhs: Terminal, rhs: Terminal) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var displayDirectory: String {
        guard let currentDirectory else { return "" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return currentDirectory.hasPrefix(home)
            ? "~" + currentDirectory.dropFirst(home.count)
            : currentDirectory
    }

    var hasChildProcess: Bool {
        !childProcesses().isEmpty
    }

    var foregroundProcessName: String? {
        childProcesses().first?.name
    }

    func terminate() {
        if let tv = localProcessTerminalView {
            let shellPid = tv.process.shellPid
            if shellPid > 0 {
                for child in childProcesses() {
                    kill(child.pid, SIGHUP)
                }
            }
            tv.process.terminate()
        }
        localProcessTerminalView = nil
    }

    func increaseFontSize() {
        guard let tv = localProcessTerminalView else { return }
        tv.font = NSFont(descriptor: tv.font.fontDescriptor, size: tv.font.pointSize + 1) ?? tv.font
    }

    func decreaseFontSize() {
        guard let tv = localProcessTerminalView else { return }
        let newSize = max(tv.font.pointSize - 1, 8)
        tv.font = NSFont(descriptor: tv.font.fontDescriptor, size: newSize) ?? tv.font
    }

    func resetFontSize() {
        guard let tv = localProcessTerminalView else { return }
        tv.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    }

    func clearTerminal() {
        guard let tv = localProcessTerminalView else { return }
        tv.getTerminal().resetToInitialState()
        tv.send(txt: "\u{0C}")
    }

    private func childProcesses() -> [(pid: pid_t, name: String)] {
        guard let tv = localProcessTerminalView else { return [] }
        let shellPid = tv.process.shellPid
        guard shellPid > 0 else { return [] }

        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size: Int = 0
        sysctl(&mib, 3, nil, &size, nil, 0)
        let count = size / MemoryLayout<kinfo_proc>.stride
        let procs = UnsafeMutablePointer<kinfo_proc>.allocate(capacity: count)
        defer { procs.deallocate() }
        sysctl(&mib, 3, procs, &size, nil, 0)
        let actualCount = size / MemoryLayout<kinfo_proc>.stride

        var children: [(pid: pid_t, name: String)] = []
        for i in 0..<actualCount {
            if procs[i].kp_eproc.e_ppid == shellPid {
                let name = withUnsafePointer(to: procs[i].kp_proc.p_comm) { ptr in
                    ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN) + 1) {
                        String(cString: $0)
                    }
                }
                children.append((procs[i].kp_proc.p_pid, name))
            }
        }
        return children
    }
}
