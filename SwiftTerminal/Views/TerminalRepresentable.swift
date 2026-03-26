import SwiftUI
import SwiftTerm

/// A single NSViewRepresentable that manages ALL terminal views at the AppKit level.
/// Terminal views are retained by TerminalTab and survive workspace/tab switches
/// by toggling `isHidden` instead of destroying/recreating views.
struct TerminalContainerRepresentable: NSViewRepresentable {
    let tabs: [TerminalTab]
    let selectedTab: TerminalTab?

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        container.wantsLayer = true
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        let coordinator = context.coordinator
        let currentTabIDs = Set(tabs.map(\.id))

        // Remove subviews for tabs no longer present
        for subview in container.subviews {
            guard let tv = subview as? LocalProcessTerminalView,
                  let tabID = coordinator.tabID(for: tv),
                  !currentTabIDs.contains(tabID) else { continue }
            tv.isHidden = true
            tv.removeFromSuperview()
        }

        // Ensure each tab has a terminal view in the container
        for tab in tabs {
            let terminalView: LocalProcessTerminalView

            if let existing = tab.localProcessTerminalView {
                terminalView = existing
                // Re-register in case the coordinator was recreated (e.g. workspace switch)
                coordinator.register(existing, for: tab)
            } else {
                terminalView = coordinator.createTerminalView(for: tab)
            }

            // Ensure delegate points to current coordinator
            terminalView.processDelegate = coordinator
            // Add to container if not already a subview
            if terminalView.superview !== container {
                terminalView.removeFromSuperview()
                terminalView.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(terminalView)
                NSLayoutConstraint.activate([
                    terminalView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                    terminalView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                    terminalView.topAnchor.constraint(equalTo: container.topAnchor),
                    terminalView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                ])
            }

            terminalView.isHidden = (tab !== selectedTab)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        /// Maps terminal view identity → (tab ID, weak tab ref) for delegate callbacks
        private var viewMap: [ObjectIdentifier: (id: UUID, tab: TerminalTab)] = [:]

        func register(_ view: LocalProcessTerminalView, for tab: TerminalTab) {
            viewMap[ObjectIdentifier(view)] = (id: tab.id, tab: tab)
        }

        func tabID(for view: LocalProcessTerminalView) -> UUID? {
            viewMap[ObjectIdentifier(view)]?.id
        }

        func createTerminalView(for tab: TerminalTab) -> LocalProcessTerminalView {
            let tv = LocalProcessTerminalView(frame: .zero)
            tv.onBell = { [weak tab, weak tv] in
                Task { @MainActor in
                    guard let tab else { return }
                    // Only badge if the tab isn't currently visible to the user
                    let isVisible = tv.map { !$0.isHidden && $0.window != nil } ?? false
                    if !isVisible {
                        tab.hasBellNotification = true
                    }
                    AppDelegate.bounceDockIcon()
                    AppDelegate.updateBadge(count: 1)
                    AppDelegate.sendNotification(
                        workspaceID: tab.workspace?.id ?? UUID(),
                        tabID: tab.id
                    )
                }
            }
            
            tv.configureNativeColors()
            tab.localProcessTerminalView = tv
            register(tv, for: tab)

            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            let shellBasename = (shell as NSString).lastPathComponent
            let shellName = "-" + shellBasename  // e.g. "-zsh" for login shell
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let startingDirectory = resolvedWorkingDirectoryPath(from: tab.currentDirectory) ?? home
            var env = ProcessInfo.processInfo.environment
            env["TERM"] = "xterm-256color"
            env["COLORTERM"] = "truecolor"

            let environment = env.map { "\($0.key)=\($0.value)" }

            tv.processDelegate = self

            tv.startProcess(
                executable: shell,
                args: [],
                environment: environment,
                execName: shellName,
                currentDirectory: startingDirectory
            )

            return tv
        }

        // MARK: - LocalProcessTerminalViewDelegate

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            guard let localProcessView = source as? LocalProcessTerminalView else { return }
            let entry = viewMap[ObjectIdentifier(localProcessView)]
            Task { @MainActor in
                entry?.tab.currentDirectory = resolvedWorkingDirectoryPath(from: directory)
            }
        }

        func processTerminated(source: TerminalView, exitCode: Int32?) {}

        private func resolvedWorkingDirectoryPath(from directory: String?) -> String? {
            guard let directory, !directory.isEmpty else { return nil }

            if let url = URL(string: directory), url.isFileURL {
                return url.path(percentEncoded: false)
            }

            return directory
        }
    }
}
