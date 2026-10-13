import Foundation
import SwiftTerm

@MainActor
enum TerminalNotificationHandler {
    /// Register directly with the parser so routing survives process-delegate changes
    /// when the same terminal view moves between tabs and inspector hosts.
    static func install(
        on view: LocalProcessTerminalView,
        notify: @escaping (TerminalNotification) -> Void,
        progress: @escaping (String) -> Void
    ) {
        view.onBell = { notify(.bell) }
        view.getTerminal().registerOscHandler(code: 9) { data in
            guard let payload = String(bytes: data, encoding: .utf8) else { return }
            if TerminalNotification.isProgressReport(payload) {
                progress(payload)
            } else if let notification = TerminalNotification.parse(osc: 9, payload: payload) {
                notify(notification)
            }
        }
        view.getTerminal().registerOscHandler(code: 777) { data in
            guard let payload = String(bytes: data, encoding: .utf8),
                  let notification = TerminalNotification.parse(osc: 777, payload: payload) else { return }
            notify(notification)
        }
    }
}
