import SwiftUI
import SwiftTerm

/// Displays a single terminal tab's view inside a SwiftUI hierarchy.
/// The `LocalProcessTerminalView` is retained by `TerminalTab` so it survives
/// tab switches without being destroyed/recreated.
struct TerminalContainerRepresentable: NSViewRepresentable {
    let tab: Terminal
    let appState: AppState

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        container.wantsLayer = true
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        let coordinator = context.coordinator
        let terminalView: LocalProcessTerminalView

        if let existing = tab.localProcessTerminalView {
            terminalView = existing
            coordinator.register(existing, for: tab)
        } else {
            terminalView = coordinator.createTerminalView(for: tab, appState: appState)
        }

        terminalView.processDelegate = coordinator

        // Add to container if not already a subview (never remove — just hide/show)
        if terminalView.superview !== container {
            terminalView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(terminalView)
            NSLayoutConstraint.activate([
                terminalView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                terminalView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                terminalView.topAnchor.constraint(equalTo: container.topAnchor),
                terminalView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }

        // Hide all, then show the selected one
        for subview in container.subviews {
            subview.isHidden = (subview !== terminalView)
        }
        terminalView.isHidden = false

        DispatchQueue.main.async {
            terminalView.window?.makeFirstResponder(terminalView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// Weak wrapper so OSC handler closures don't retain the Terminal model.
    private final class WeakTab {
        weak var value: Terminal?
        init(_ value: Terminal) { self.value = value }
    }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        /// SwiftTerm parses OSC 7 (`\e]7;file://host/path\a`) and forwards the
        /// reported directory here. The shell-integration scripts emit this on
        /// every prompt and on `chpwd`, so this is the authoritative source for
        /// the per-tab `currentDirectory` — no polling required.
        func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {
            guard let directory,
                  let local = source as? LocalProcessTerminalView,
                  let entry = viewMap[ObjectIdentifier(local)] else { return }
            let path: String
            if let url = URL(string: directory), url.isFileURL {
                path = url.path(percentEncoded: false)
            } else {
                path = directory
            }
            guard !path.isEmpty else { return }
            DispatchQueue.main.async {
                if entry.tab.currentDirectory != path {
                    entry.tab.currentDirectory = path
                }
            }
        }

        private var viewMap: [ObjectIdentifier: (id: UUID, tab: Terminal)] = [:]

        func register(_ view: LocalProcessTerminalView, for tab: Terminal) {
            viewMap[ObjectIdentifier(view)] = (id: tab.id, tab: tab)
        }

        func createTerminalView(for tab: Terminal, appState: AppState) -> LocalProcessTerminalView {
            let tv = LocalProcessTerminalView(frame: .zero)
            tv.onBell = { [weak tab, weak tv, weak appState] in
                Task { @MainActor in
                    guard let tab else { return }
                    let isSelected = appState?.selectedTerminal === tab
                    let isVisible = isSelected && (tv.map { !$0.isHidden && $0.window != nil } ?? false)
                    if !isVisible {
                        tab.hasBellNotification = true
                    }
                    AppDelegate.bounceDockIcon()
                    if !NSApplication.shared.isActive {
                        AppDelegate.showBadge()
                    }
                    if let workspaceID = tab.workspace?.id {
                        AppDelegate.sendNotification(workspaceID: workspaceID, terminalID: tab.id)
                    }
                }
            }

            tv.configureNativeColors()
            tv.getTerminal().setCursorStyle(.blinkBar)
            tv.font = NSFont(descriptor: tv.font.fontDescriptor, size: TerminalProcessRegistry.fontSize) ?? tv.font
            tab.localProcessTerminalView = tv
            register(tv, for: tab)

            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            let shellBasename = (shell as NSString).lastPathComponent
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            // Prefer the tab's own cwd (set by tab-bar terminals on creation, then
            // kept current via OSC 7). Fall back to the workspace directory so
            // commands — which never set currentDirectory — spawn in the project
            // root instead of $HOME.
            let startingDirectory = resolvedWorkingDirectoryPath(from: tab.currentDirectory)
                ?? resolvedWorkingDirectoryPath(from: tab.workspace?.directory)
                ?? home

            let plan = ShellIntegration.plan(forShellPath: shell)

            var env = ProcessInfo.processInfo.environment
            env["TERM"] = "xterm-256color"
            env["COLORTERM"] = "truecolor"
            for (k, v) in plan.env { env[k] = v }
            let environment = env.map { "\($0.key)=\($0.value)" }

            // bash --rcfile only takes effect for non-login shells, so when our
            // plan injects rc args we must drop the leading-dash login convention.
            let execName = plan.args.contains("--rcfile") ? shellBasename : "-" + shellBasename

            tv.processDelegate = self

            installSemanticPromptHandler(on: tv, for: tab)
            installProgressReportHandler(on: tv, for: tab)

            tv.startProcess(
                executable: shell,
                args: plan.args,
                environment: environment,
                execName: execName,
                currentDirectory: startingDirectory
            )

            return tv
        }

        // MARK: - LocalProcessTerminalViewDelegate

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

        /// SwiftTerm calls this for OSC 0/1/2 (window/icon title). Programs like
        /// vim, ssh, and tmux freely overwrite the title, so it is *not* a
        /// reliable signal for whether a command is running — the OSC 133
        /// delegate methods below own that state. We intentionally ignore the
        /// title for state tracking.
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            guard let local = source as? LocalProcessTerminalView,
                  let entry = viewMap[ObjectIdentifier(local)] else { return }
            DispatchQueue.main.async {
                entry.tab.foregroundProcessName = nil
                entry.tab.progressState = nil
                entry.tab.progressValue = nil
            }
            viewMap.removeValue(forKey: ObjectIdentifier(local))
        }

        /// Registers an OSC 133 (FinalTerm semantic prompt) handler on the
        /// underlying `Terminal`. The shell-integration scripts emit:
        ///   - `\e]133;C;<command>\a` when a foreground command starts
        ///   - `\e]133;D;<exit>\a`    when it finishes
        /// Attaching the handler to the SwiftTerm parser (rather than
        /// `processDelegate`) means it survives the same terminal being shown
        /// in multiple `TerminalContainerRepresentable` instances (main tab
        /// bar + commands inspector), which would otherwise fight over the
        /// delegate and silence updates for one of them.
        func installSemanticPromptHandler(on view: LocalProcessTerminalView, for tab: Terminal) {
            let weakTab = WeakTab(tab)
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
                    DispatchQueue.main.async {
                        guard let tab = weakTab.value else { return }
                        if tab.foregroundProcessName != value {
                            tab.foregroundProcessName = value
                        }
                    }
                case "D":
                    let exit = Int32(arg.trimmingCharacters(in: .whitespacesAndNewlines))
                    DispatchQueue.main.async {
                        guard let tab = weakTab.value else { return }
                        tab.foregroundProcessName = nil
                        tab.lastExitCode = exit
                        tab.progressState = nil
                        tab.progressValue = nil
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
        /// to surface progress in the tab UI instead.
        func installProgressReportHandler(on view: LocalProcessTerminalView, for tab: Terminal) {
            let weakTab = WeakTab(tab)
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

                DispatchQueue.main.async {
                    guard let tab = weakTab.value else { return }
                    if rawState == 0 {  // remove
                        tab.progressState = nil
                        tab.progressValue = nil
                        return
                    }
                    guard let state = TerminalProgressState(rawValue: rawState) else { return }
                    tab.progressState = state
                    switch state {
                    case .set, .error:
                        tab.progressValue = progress ?? tab.progressValue ?? 0
                    case .indeterminate:
                        tab.progressValue = nil
                    case .pause:
                        tab.progressValue = progress ?? tab.progressValue
                    }
                }
            }
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
