import Foundation

/// Notification content from the terminal, independent of the emitting CLI.
struct TerminalNotification: Equatable, Sendable {
    let title: String?
    let body: String?

    static let bell = Self(title: nil, body: nil)

    static func isProgressReport(_ payload: String) -> Bool {
        payload == "4" || payload.hasPrefix("4;")
    }

    static func parse(osc code: Int, payload: String) -> Self? {
        switch code {
        case 9:
            guard !isProgressReport(payload), !payload.isEmpty else { return nil }
            return Self(title: nil, body: payload)
        case 777:
            let parts = payload.split(separator: ";", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3, parts[0] == "notify" else { return nil }
            let title = String(parts[1])
            let body = String(parts[2])
            guard !title.isEmpty || !body.isEmpty else { return nil }
            return Self(title: title.isEmpty ? nil : title, body: body.isEmpty ? nil : body)
        default:
            return nil
        }
    }
}
