import SwiftUI
import AppKit

/// Window-scoped mouse monitor that sets `focusedPaneID` when the user clicks
/// inside a pane. The event is returned unchanged so the terminal still handles
/// it. Mounted once per split tab via `.background` in the detail view.
struct PaneFocusTracker: NSViewRepresentable {
    let appState: AppState
    let tab: Terminal

    func makeNSView(context: Context) -> NSView {
        context.coordinator.appState = appState
        context.coordinator.tab = tab
        context.coordinator.start()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.appState = appState
        context.coordinator.tab = tab
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var appState: AppState?
        var tab: Terminal?
        private var monitor: Any?

        func start() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                self?.handle(event)
                return event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func handle(_ event: NSEvent) {
            guard let appState, let tab, appState.isTabSplit(tab),
                  let window = event.window else { return }
            let location = event.locationInWindow
            for terminal in appState.paneTerminals(for: tab) {
                guard let view = terminal.localProcessTerminalView, view.window === window else { continue }
                if view.convert(view.bounds, to: nil).contains(location) {
                    if appState.focusedPaneID != terminal.id {
                        appState.focusedPaneID = terminal.id
                    }
                    break
                }
            }
        }
    }
}
