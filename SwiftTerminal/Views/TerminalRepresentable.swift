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
                    AppDelegate.updateBadge(count: 1)
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
            let startingDirectory = resolvedWorkingDirectoryPath(from: tab.currentDirectory) ?? home

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
            }
            viewMap.removeValue(forKey: ObjectIdentifier(local))
        }

        /// SwiftTerm parses OSC 133;C (FinalTerm semantic prompt — command
        /// started) and forwards the result here. The shell-integration scripts
        /// emit this on `preexec`, making it the authoritative "shell is busy"
        /// signal, independent of window title or child-process scanning.
        func semanticPromptCommandStarted(source: TerminalView, command: String?) {
            guard let local = source as? LocalProcessTerminalView,
                  let entry = viewMap[ObjectIdentifier(local)] else { return }
            let value = (command?.isEmpty == false) ? command! : "(running)"
            DispatchQueue.main.async {
                if entry.tab.foregroundProcessName != value {
                    entry.tab.foregroundProcessName = value
                }
            }
        }

        /// SwiftTerm parses OSC 133;D (command finished) and forwards the exit
        /// code here. Clears `foregroundProcessName` so the inspector goes back
        /// to "idle" and records `lastExitCode` for future status display.
        func semanticPromptCommandFinished(source: TerminalView, exitCode: Int32?) {
            guard let local = source as? LocalProcessTerminalView,
                  let entry = viewMap[ObjectIdentifier(local)] else { return }
            DispatchQueue.main.async {
                entry.tab.foregroundProcessName = nil
                entry.tab.lastExitCode = exitCode
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
