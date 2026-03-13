#if os(macOS)
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
            tab.localProcessTerminalView = tv
            register(tv, for: tab)

            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            let shellName = "-" + (shell as NSString).lastPathComponent  // e.g. "-zsh" for login shell
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            var env = ProcessInfo.processInfo.environment
            env["TERM"] = "xterm-256color"
            env["COLORTERM"] = "truecolor"
            let environment = env.map { "\($0.key)=\($0.value)" }

            tv.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            tv.processDelegate = self

            tv.startProcess(
                executable: shell,
                args: [],
                environment: environment,
                execName: shellName,
                currentDirectory: home
            )

            return tv
        }

        // MARK: - LocalProcessTerminalViewDelegate

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            let entry = viewMap[ObjectIdentifier(source)]
            Task { @MainActor in
                entry?.tab.title = title.isEmpty ? "Terminal" : title
            }
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func processTerminated(source: TerminalView, exitCode: Int32?) {}
    }
}
#endif
