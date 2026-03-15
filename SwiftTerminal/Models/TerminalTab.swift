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
    var hasBellNotification = false
    var workspaceID: UUID?
    var localProcessTerminalView: LocalProcessTerminalView?
    var isProcessActive = false
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

    var displayDirectory: String {
        guard let currentDirectory else { return "" }
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        if currentDirectory.hasPrefix(homeDirectory) {
            let relativePath = String(currentDirectory.dropFirst(homeDirectory.count))
            return "~" + relativePath
        }
        return currentDirectory
    }

    func terminate() {
        // LocalProcessTerminalView cleans up its process on dealloc
        localProcessTerminalView = nil
    }

    func rename(to name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard title != trimmedName else { return }
        title = trimmedName
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
