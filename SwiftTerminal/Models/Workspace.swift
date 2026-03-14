import Foundation

@Observable
final class Workspace: Identifiable {
    let id: UUID
    var name: String {
        didSet {
            guard name != oldValue else { return }
            onPersistChange?()
        }
    }
    var tabs: [TerminalTab] = [] {
        didSet {
            configureTabPersistence()
            onPersistChange?()
        }
    }
    var selectedTab: TerminalTab? {
        didSet {
            guard selectedTab?.id != oldValue?.id else { return }
            onPersistChange?()
        }
    }
    var onPersistChange: (() -> Void)? {
        didSet {
            configureTabPersistence()
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        tabs: [TerminalTab] = [],
        selectedTabID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.tabs = tabs
        self.selectedTab = tabs.first { $0.id == selectedTabID } ?? tabs.first
        configureTabPersistence()
    }

    @discardableResult
    func addTab(currentDirectory: String? = nil) -> TerminalTab {
        let tab = TerminalTab(currentDirectory: currentDirectory)
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

    private func configureTabPersistence() {
        for tab in tabs {
            tab.onPersistChange = onPersistChange
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
