import Foundation

enum ThreadListSection: String, CaseIterable, Identifiable {
    case priority = "Priority"
    case today = "Today"
    case yesterday = "Yesterday"
    case earlier = "Earlier"

    var id: Self { self }
}
