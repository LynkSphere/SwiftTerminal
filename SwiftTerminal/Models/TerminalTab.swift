import Foundation
import SwiftTerm

@Observable
final class TerminalTab: Identifiable {
    let id = UUID()
    var title: String = "Terminal"
    var localProcessTerminalView: LocalProcessTerminalView?

    func terminate() {
        // LocalProcessTerminalView cleans up its process on dealloc
        localProcessTerminalView = nil
    }
}

extension TerminalTab: Hashable {
    static func == (lhs: TerminalTab, rhs: TerminalTab) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
