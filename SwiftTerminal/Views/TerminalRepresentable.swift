import SwiftUI
import SwiftTerm

/// Hosts a retained terminal process for a task or inspector command.
struct TerminalContainerRepresentable: NSViewRepresentable {
    let terminal: Terminal
    let appState: AppState

    func makeNSView(context: Context) -> TerminalHostView {
        let container = TerminalHostView(frame: .zero)
        container.wantsLayer = true
        return container
    }

    func updateNSView(_ container: TerminalHostView, context: Context) {
        // A retiring host must not recreate a process after its session is closed.
        guard !terminal.hasExited || terminal.localProcessTerminalView != nil else { return }
        let coordinator = context.coordinator
        let terminalView: LocalProcessTerminalView

        if let existing = terminal.localProcessTerminalView {
            terminalView = existing
        } else {
            terminalView = coordinator.createTerminalView(for: terminal, appState: appState)
        }

        terminalView.processDelegate = terminal.processDelegate

        container.host(terminalView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// Weak wrapper so OSC handler closures don't retain the Terminal model.
    final class WeakTerminal {
        weak var value: Terminal?
        init(_ value: Terminal) { self.value = value }
    }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        /// SwiftTerm parses OSC 7 (`\e]7;file://host/path\a`) and forwards the
        /// reported directory here. The shell-integration scripts emit this on
        /// every prompt and on `chpwd`, so this is the authoritative source for
        /// the per-terminal `currentDirectory` — no polling required.
        func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {
            guard let directory,
                  let local = source as? LocalProcessTerminalView,
                  let terminal = viewMap[ObjectIdentifier(local)]?.value else { return }
            let path: String
            if let url = URL(string: directory), url.isFileURL {
                path = url.path(percentEncoded: false)
            } else {
                path = directory
            }
            guard !path.isEmpty else { return }
            Task { @MainActor in
                if terminal.currentDirectory != path {
                    terminal.currentDirectory = path
                }
            }
        }

        private var viewMap: [ObjectIdentifier: WeakTerminal] = [:]

        func register(_ view: LocalProcessTerminalView, for terminal: Terminal) {
            viewMap[ObjectIdentifier(view)] = WeakTerminal(terminal)
        }

        func createTerminalView(for terminal: Terminal, appState: AppState) -> LocalProcessTerminalView {
            let tv = LocalProcessTerminalView(frame: .zero)
            tv.onBell = { [weak terminal, weak tv, weak appState] in
                Task { @MainActor in
                    guard let terminal else { return }
                    let isSelected = appState?.activeTerminal === terminal
                    let isVisible = isSelected && (tv?.window != nil)
                    if !isVisible {
                        terminal.hasBellNotification = true
                    }
                    AppDelegate.bounceDockIcon()
                    if !NSApplication.shared.isActive {
                        AppDelegate.showBadge()
                    }
                    if let workspaceID = terminal.workspace?.id {
                        AppDelegate.sendNotification(
                            workspaceID: workspaceID,
                            terminalID: terminal.id,
                            workspaceName: terminal.workspace?.name,
                            terminalName: terminal.displayTitle
                        )
                    }
                }
            }

            tv.configureNativeColors()
            try? tv.setUseMetal(true)
            tv.getTerminal().setCursorStyle(.steadyBlock)
            tv.getTerminal().changeScrollback(TerminalProcessRegistry.scrollback)
            let fontSize = terminal.isTaskTerminal ? TerminalProcessRegistry.fontSize : TerminalProcessRegistry.commandFontSize
            tv.font = NSFont(descriptor: tv.font.fontDescriptor, size: fontSize) ?? tv.font
            terminal.localProcessTerminalView = tv
            terminal.processDelegate = self
            terminal.hasExited = false
            register(tv, for: terminal)

            let launch = terminal.pendingLaunch
            let shell = launch == nil ? (ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh") : IntegrationProcess.shell
            let shellBasename = (shell as NSString).lastPathComponent
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let startingDirectory = resolvedWorkingDirectoryPath(from: terminal.currentDirectory)
                ?? resolvedWorkingDirectoryPath(from: terminal.workspace?.directory)
                ?? home

            let plan: ShellIntegration.Plan
            if let launch {
                // Use argv, not PTY input: long settings exceed the terminal's canonical
                // input limit, and shell startup can consume input before its first prompt.
                plan = ShellIntegration.Plan(
                    args: IntegrationProcess.shellArguments(command: launch.executable, arguments: launch.arguments), env: [:]
                )
                terminal.foregroundProcessName = launch.executable
            } else {
                plan = ShellIntegration.plan(forShellPath: shell)
            }

            var env = launch == nil ? ProcessInfo.processInfo.environment : IntegrationProcess.environment
            env["TERM"] = "xterm-256color"
            env["COLORTERM"] = "truecolor"
            for (k, v) in plan.env { env[k] = v }
            let environment = env.map { "\($0.key)=\($0.value)" }

            // bash --rcfile only takes effect for non-login shells, so when our
            // plan injects rc args we must drop the leading-dash login convention.
            let execName = launch != nil || plan.args.contains("--rcfile") ? shellBasename : "-" + shellBasename

            tv.processDelegate = self

            installSemanticPromptHandler(on: tv, for: terminal)
            installProgressReportHandler(on: tv, for: terminal)

            tv.startProcess(
                executable: shell,
                args: plan.args,
                environment: environment,
                execName: execName,
                currentDirectory: startingDirectory
            )

            terminal.pendingLaunch = nil

            return tv
        }

        // MARK: - LocalProcessTerminalViewDelegate

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            guard let terminal = viewMap[ObjectIdentifier(source)]?.value else { return }
            Task { @MainActor [weak terminal] in
                guard let terminal, terminal.reportedTerminalTitle != title else { return }
                terminal.reportedTerminalTitle = title
                terminal.onTitleChange?(title)
            }
        }

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            guard let local = source as? LocalProcessTerminalView,
                  let terminal = viewMap[ObjectIdentifier(local)]?.value else { return }
            Task { @MainActor in
                terminal.foregroundProcessName = nil
                terminal.reportedTerminalTitle = nil
                terminal.progressState = nil
                terminal.progressValue = nil
                terminal.lastExitCode = exitCode
                terminal.hasExited = true
                terminal.onProcessExit?(exitCode)
            }
            viewMap.removeValue(forKey: ObjectIdentifier(local))
        }

        func installSemanticPromptHandler(on view: LocalProcessTerminalView, for terminal: Terminal) {
            let weakTerminal = WeakTerminal(terminal)
            view.getTerminal().registerOscHandler(code: 133) { data in
                let payload = String(bytes: data, encoding: .utf8) ?? ""
                let verb: String
                let arg: String
                if let semi = payload.firstIndex(of: ";") {
                    verb = String(payload[..<semi])
                    arg = String(payload[payload.index(after: semi)...])
                } else {
                    verb = payload
                    arg = ""
                }
                switch verb {
                case "C":
                    let name = arg.trimmingCharacters(in: .whitespacesAndNewlines)
                    let value = name.isEmpty ? "(running)" : name
                    Task { @MainActor in
                        guard let terminal = weakTerminal.value else { return }
                        terminal.reportedTerminalTitle = nil
                        if terminal.foregroundProcessName != value {
                            terminal.foregroundProcessName = value
                        }
                    }
                case "D":
                    let exit = Int32(arg.trimmingCharacters(in: .whitespacesAndNewlines))
                    Task { @MainActor in
                        guard let terminal = weakTerminal.value else { return }
                        terminal.foregroundProcessName = nil
                        terminal.reportedTerminalTitle = nil
                        terminal.lastExitCode = exit
                        terminal.progressState = nil
                        terminal.progressValue = nil
                    }
                default:
                    break  // 133;A (prompt-start) and 133;B (prompt-end) ignored
                }
            }
        }

        /// Registers an OSC 9;4 (ConEmu progress report) handler. Payload shape:
        ///   `9;4;<state>[;<progress>]` where state is 0=remove, 1=set,
        ///   2=error, 3=indeterminate, 4=pause; progress is 0…100.
        /// Preempts SwiftTerm's built-in `oscProgressReport` (which would
        /// otherwise render a thin bar at the terminal's bottom edge); we want
        /// to surface progress in the inspector instead.
        func installProgressReportHandler(on view: LocalProcessTerminalView, for terminal: Terminal) {
            let weakTerminal = WeakTerminal(terminal)
            view.getTerminal().registerOscHandler(code: 9) { data in
                let payload = String(bytes: data, encoding: .utf8) ?? ""
                // Only `4;…` is a progress report; ignore other OSC 9 forms.
                let parts = payload.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
                guard parts.first == "4", parts.count >= 2,
                      let rawState = Int(parts[1]) else { return }

                let progress: UInt8? = {
                    guard parts.count >= 3, let raw = Int(parts[2]) else { return nil }
                    return UInt8(max(0, min(raw, 100)))
                }()

                Task { @MainActor in
                    guard let terminal = weakTerminal.value else { return }
                    if rawState == 0 {  // remove
                        terminal.progressState = nil
                        terminal.progressValue = nil
                        return
                    }
                    guard let state = TerminalProgressState(rawValue: rawState) else { return }
                    terminal.progressState = state
                    switch state {
                    case .set, .error:
                        terminal.progressValue = progress ?? terminal.progressValue ?? 0
                    case .indeterminate:
                        terminal.progressValue = nil
                    case .pause:
                        terminal.progressValue = progress ?? terminal.progressValue
                    }
                }
            }
        }

        /// SwiftTerm reposts link activation (click on an OSC 8 hyperlink or an
        /// implicitly detected URL/path) here. A link that resolves to a file
        /// inside the terminal's workspace opens in the bottom editor panel — same
        /// as clicking it in the file tree; everything else keeps SwiftTerm's
        /// default NSWorkspace behavior.
        func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String: String]) {
            let terminal = (source as? LocalProcessTerminalView)
                .flatMap { viewMap[ObjectIdentifier($0)]?.value }
            Task { @MainActor [weak self] in
                if let self, let terminal, let target = self.workspaceFileTarget(for: link, terminal: terminal) {
                    terminal.workspace?.editorPanel.openFile(target.url, scrollToLine: target.line)
                    return
                }
                if let url = URL(string: link) {
                    NSWorkspace.shared.open(url)
                }
            }
        }

        /// Resolves a clicked link to a file inside the terminal's workspace, or nil
        /// if it isn't one. Handles `file:` URLs, absolute, `~/`, and relative
        /// paths (resolved against the terminal's cwd, then the workspace root, so
        /// workspace-relative paths printed by tools resolve even when the
        /// shell's cwd is elsewhere), plus a trailing `:line[:column]` suffix
        /// from compiler-style output.
        private func workspaceFileTarget(for link: String, terminal: Terminal) -> (url: URL, line: Int?)? {
            guard let workspace = terminal.workspace else { return nil }

            let rawPath: String
            if link.hasPrefix("file:") {
                guard let url = URL(string: link), url.isFileURL else { return nil }
                rawPath = url.path(percentEncoded: false)
            } else if link.contains("://") {
                return nil
            } else {
                rawPath = link
            }

            var candidates: [(path: String, line: Int?)] = [(rawPath, nil)]
            if let match = rawPath.wholeMatch(of: /(.+?):(\d+)(?::\d+)?/) {
                candidates.append((String(match.1), Int(match.2)))
            }

            let roots = [workspace.effectiveURL, workspace.url].map { $0.standardizedFileURL.path }
            let cwd = resolvedWorkingDirectoryPath(from: terminal.currentDirectory) ?? workspace.directory
            for (path, line) in candidates {
                let resolved: [URL]
                if path.hasPrefix("/") {
                    resolved = [URL(fileURLWithPath: path)]
                } else if path == "~" || path.hasPrefix("~/") {
                    resolved = [URL(fileURLWithPath: (path as NSString).expandingTildeInPath)]
                } else {
                    resolved = ([cwd] + roots).map { URL(fileURLWithPath: $0).appending(path: path) }
                }
                for url in resolved.map(\.standardizedFileURL) {
                    var isDirectory: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                          !isDirectory.boolValue else { continue }
                    guard roots.contains(where: { url.path == $0 || url.path.hasPrefix($0 + "/") }) else { continue }
                    return (url, line)
                }
            }
            return nil
        }

        private func resolvedWorkingDirectoryPath(from directory: String?) -> String? {
            guard let directory, !directory.isEmpty else { return nil }

            if let url = URL(string: directory), url.isFileURL {
                return url.path(percentEncoded: false)
            }

            return directory
        }
    }
}
