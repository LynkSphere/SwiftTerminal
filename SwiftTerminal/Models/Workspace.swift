import Foundation

@Observable
final class Workspace: Identifiable {
    let id = UUID()
    var name: String
    var tabs: [TerminalTab] = []
    var selectedTab: TerminalTab?

    init(name: String) {
        self.name = name
    }

    @discardableResult
    func addTab() -> TerminalTab {
        let tab = TerminalTab()
        tabs.append(tab)
        selectedTab = tab
        return tab
    }

    func closeTab(_ tab: TerminalTab) {
        tab.terminate()
        tabs.removeAll { $0.id == tab.id }
        if selectedTab === tab {
            selectedTab = tabs.last
        }
    }

    func terminateAll() {
        for tab in tabs {
            tab.terminate()
        }
    }
}

extension Workspace: Hashable {
    static func == (lhs: Workspace, rhs: Workspace) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
