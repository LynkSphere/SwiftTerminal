import Foundation
import SwiftData

@Model
final class Workspace {
    var id = UUID()
    var name: String = ""
    var sortOrder: Int = 0
    
    var directory: String = ""
    var url: URL {
        URL(fileURLWithPath: directory)
    }

    @Relationship(deleteRule: .cascade)
    var unsortedSessions: [ClaudeSession] = []
    var sessions: [ClaudeSession] {
        unsortedSessions.sorted { $0.createdAt < $1.createdAt }
    }

    @Relationship(deleteRule: .cascade, inverse: \TerminalTab.workspace)
    var unsortedTerminals: [TerminalTab] = []
    var terminals: [TerminalTab] {
        unsortedTerminals.sorted { $0.sortOrder < $1.sortOrder }
    }

    init(name: String, directory: String, sortOrder: Int = 0) {
        self.name = name
        self.directory = directory
        self.sortOrder = sortOrder
    }
    
    // MARK: - Session Management

    @discardableResult
    func newSession() -> ClaudeSession {
        let cs = ClaudeSession(workspace: self)
        unsortedSessions.append(cs)
        return cs
    }

    func removeSession(_ cs: ClaudeSession) {
        cs.service?.stop()
        unsortedSessions.removeAll { $0.id == cs.id }
        cs.modelContext?.delete(cs)
    }

    // MARK: - Terminal Management

    @discardableResult
    func addTerminal() -> TerminalTab {
        let tab = TerminalTab(currentDirectory: directory, sortOrder: unsortedTerminals.count)
        unsortedTerminals.append(tab)
        return tab
    }

    func closeTerminal(_ tab: TerminalTab) {
        tab.terminate()
        unsortedTerminals.removeAll { $0.id == tab.id }
        tab.modelContext?.delete(tab)
    }
}
