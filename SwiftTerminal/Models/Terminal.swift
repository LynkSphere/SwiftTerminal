import AppKit
import Observation
import SwiftTerm

/// Mirrors `SwiftTerm.Terminal.ProgressReportState` so the model layer doesn't
/// expose the dependency type. Driven by OSC 9;4 (ConEmu progress).
enum TerminalProgressState: Int {
    case set = 1
    case error = 2
    case indeterminate = 3
    case pause = 4
}

@Observable
final class Terminal: Identifiable, Hashable, Codable {
    var id: UUID

    var title: String
    var currentDirectory: String?

    /// When set, this terminal represents a saved "command" the user can run on demand.
    /// Sending the script appends a newline so the shell executes it.
    var runScript: String?

    /// Passed as process arguments, never typed into an interactive shell's input buffer.
    var pendingLaunch: AgentLaunch?
    var hasExited = false

    @ObservationIgnored
    var processDelegate: (any LocalProcessTerminalViewDelegate)?

    @ObservationIgnored
    var onProcessExit: (@MainActor (Int32?) -> Void)?

    @ObservationIgnored
    var onTitleChange: (@MainActor (String) -> Void)?

    /// Whether this saved command is the workspace's default "Run" target (Cmd+R).
    /// Only meaningful for entries in `Workspace.commands`; unused for tasks.
    var isDefault: Bool = false

    /// Name of the current foreground child process, if any. Driven by the
    /// shell-integration OSC 133 handler installed in `TerminalRepresentable`:
    /// set on `133;C` (preexec), cleared on `133;D` (precmd).
    var foregroundProcessName: String?

    /// Most recent OSC 0/1/2 title reported by the foreground program. This is
    /// session-only and is surfaced only while Claude Code or Codex is active.
    var reportedTerminalTitle: String?

    /// Exit status of the most recently completed foreground command, surfaced
    /// by OSC 133;D. Nil before the first command finishes.
    var lastExitCode: Int32?

    /// Most recent OSC 9;4 progress report from the running foreground command
    /// (ConEmu/Windows-Terminal "progress" spec). Set by the OSC 9 handler in
    /// `TerminalRepresentable`, cleared on OSC 133;D and on process exit.
    var progressState: TerminalProgressState?

    /// 0…100 when `progressState == .set` or `.error`; nil otherwise.
    var progressValue: UInt8?

    @ObservationIgnored
    weak var workspace: Workspace?

    /// Not encoded; reset per launch.
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

    init(workspace: Workspace, title: String = "", currentDirectory: String? = nil, runScript: String? = nil) {
        self.id = UUID()
        self.workspace = workspace
        self.title = title
        self.currentDirectory = currentDirectory
        self.runScript = runScript
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, title, currentDirectory, runScript, isDefault
        // Legacy CommandEntry keys retained so old workspaces.json decodes.
        case name, command
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        if let title = try c.decodeIfPresent(String.self, forKey: .title) {
            self.title = title
        } else if let name = try c.decodeIfPresent(String.self, forKey: .name) {
            self.title = name
        } else {
            self.title = ""
        }
        self.currentDirectory = try c.decodeIfPresent(String.self, forKey: .currentDirectory)
        if let script = try c.decodeIfPresent(String.self, forKey: .runScript) {
            self.runScript = script
        } else if let legacy = try c.decodeIfPresent(String.self, forKey: .command) {
            self.runScript = legacy
        } else {
            self.runScript = nil
        }
        self.isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(currentDirectory, forKey: .currentDirectory)
        try c.encodeIfPresent(runScript, forKey: .runScript)
        if isDefault { try c.encode(isDefault, forKey: .isDefault) }
    }

    // MARK: - Hashable

    static func == (lhs: Terminal, rhs: Terminal) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// A user-set name wins, followed by
    /// an active Claude/Codex chat title, the foreground process, and finally
    /// the generic "Terminal" label.
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasCustomTitle = !trimmed.isEmpty && trimmed != "Terminal"
        if hasCustomTitle { return trimmed }
        if let agentTitle = AgentTerminalTitle.displayTitle(
            reportedTitle: reportedTerminalTitle,
            foregroundCommand: foregroundProcessName
        ) {
            return agentTitle
        }
        if let foregroundProcessName, !foregroundProcessName.isEmpty { return foregroundProcessName }
        return trimmed.isEmpty ? "Terminal" : trimmed
    }

    var displayDirectory: String {
        guard let currentDirectory else { return "" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return currentDirectory.hasPrefix(home)
            ? "~" + currentDirectory.dropFirst(home.count)
            : currentDirectory
    }

    var hasChildProcess: Bool {
        foregroundProcessName != nil
    }

    func terminate() {
        // An intentional close must not report a late process exit as task activity.
        onProcessExit = nil
        onTitleChange = nil
        if let tv = localProcessTerminalView {
            tv.processDelegate = nil
            tv.onBell = nil
            if tv.process.running {
                let pid = tv.process.shellPid
                for child in childProcesses() {
                    kill(child.pid, SIGHUP)
                }
                tv.process.terminate()
                if pid > 0 {
                    Task.detached {
                        await Terminal.reapTerminatedProcess(pid)
                    }
                }
            }
            tv.removeFromSuperview()
        }
        localProcessTerminalView = nil
        pendingLaunch = nil
        processDelegate = nil
        hasExited = true
        foregroundProcessName = nil
        reportedTerminalTitle = nil
        progressState = nil
        progressValue = nil
        hasBellNotification = false
    }

    /// SwiftTerm cancels its child monitor during termination, so we must reap
    /// the child ourselves. Capture only its PID so cleanup retains no UI state.
    nonisolated private static func reapTerminatedProcess(_ pid: pid_t) async {
        let clock = ContinuousClock()
        var deadline = clock.now + .seconds(1)
        var sentKill = false
        while true {
            var status: Int32 = 0
            let result = waitpid(pid, &status, WNOHANG)
            if result == -1, errno == EINTR { continue }
            guard result == 0 else { return }

            if clock.now >= deadline {
                guard !sentKill else { return }
                // A zero waitpid result confirms this is still our live child.
                kill(pid, SIGKILL)
                sentKill = true
                deadline = clock.now + .seconds(1)
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    func increaseFontSize() {
        TerminalProcessRegistry.fontSize += 0.5
    }

    func decreaseFontSize() {
        TerminalProcessRegistry.fontSize -= 0.5
    }

    func resetFontSize() {
        TerminalProcessRegistry.fontSize = TerminalProcessRegistry.defaultFontSize
    }

    func clearTerminal() {
        guard let tv = localProcessTerminalView else { return }
        tv.getTerminal().resetToInitialState()
        tv.send(txt: "\u{0C}")
    }

    /// Sends `runScript` to the shell if one is configured and the terminal is live.
    /// Caller is responsible for ensuring the view exists first (selecting the terminal
    /// creates it); see `Workspace.runCommand(_:)` for the full flow.
    func run() {
        guard let script = runScript?.trimmingCharacters(in: .whitespacesAndNewlines),
              !script.isEmpty,
              let tv = localProcessTerminalView else { return }
        if let dir = workspace?.directory, !dir.isEmpty {
            let escaped = dir
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            tv.send(txt: "cd \"\(escaped)\"\n")
        }
        clearTerminal()
        tv.send(txt: script + "\n")
    }

    /// Sends Ctrl+C to interrupt the running foreground process.
    func interrupt() {
        localProcessTerminalView?.send(txt: "\u{03}")
    }

    func childProcesses() -> [(pid: pid_t, name: String)] {
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
