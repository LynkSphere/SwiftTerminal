import SwiftUI
import AppKit

struct PaneFocusTracker: NSViewRepresentable {
    let tab: WorkspaceTab

    func makeNSView(context: Context) -> NSView {
        context.coordinator.tab = tab
        context.coordinator.start()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.tab = tab
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var tab: WorkspaceTab?
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
            guard let tab, tab.isSplit,
                  let window = event.window else { return }
            let location = event.locationInWindow
            for pane in tab.panes {
                guard let view = pane.paneView, view.window === window else { continue }
                if view.convert(view.bounds, to: nil).contains(location) {
                    if tab.focusedPane !== pane {
                        tab.focus(pane)
                    }
                    break
                }
            }
        }
    }
}
