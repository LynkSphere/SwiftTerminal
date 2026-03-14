import Foundation
import SwiftTerm

@Observable
final class TerminalTab: Identifiable {
    let id: UUID
    var title: String = "Terminal" {
        didSet {
            guard title != oldValue else { return }
            onPersistChange?()
        }
    }
    var currentDirectory: String? {
        didSet {
            guard currentDirectory != oldValue else { return }
            onPersistChange?()
        }
    }
    var localProcessTerminalView: LocalProcessTerminalView?
    var onPersistChange: (() -> Void)?

    init(
        id: UUID = UUID(),
        title: String = "Terminal",
        currentDirectory: String? = nil
    ) {
        self.id = id
        self.title = title
        self.currentDirectory = currentDirectory
    }

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
