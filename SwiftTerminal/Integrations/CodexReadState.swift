import Foundation

struct CodexReadState: Sendable, Equatable {
    let revision: String
    let isUnread: Bool

    init?(_ value: [String: Any]?) {
        guard let value, let revision = value["revision"] as? String else { return nil }
        self.revision = revision
        isUnread = value["firstUnread"] as? [String: Any] != nil
    }
}
