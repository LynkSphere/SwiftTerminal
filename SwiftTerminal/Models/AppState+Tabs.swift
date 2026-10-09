import Foundation

extension AppState {
    var selectedPane: Pane? { selectedTab?.focusedPane }

    func selectTabIfPresent(_ tab: WorkspaceTab, in workspace: Workspace) {
        guard tab.workspace === workspace,
              workspace.tabs.contains(where: { $0 === tab }) else { return }
        selectedTab = tab
    }

    func requestCloseTab(_ tab: WorkspaceTab) {
        if tab.panes.contains(where: { $0.terminal?.hasChildProcess == true }) {
            tabPendingClose = tab
        } else {
            closeTab(tab)
        }
    }

    func requestClosePane(_ pane: Pane, in tab: WorkspaceTab) {
        if pane.terminal?.hasChildProcess == true {
            panePendingClose = pane
        } else {
            closePane(pane, in: tab)
        }
    }

    func closeTab(_ tab: WorkspaceTab) {
        guard let workspace = tab.workspace,
              workspace.tabs.contains(where: { $0 === tab }) else { return }
        let next = workspace.tabAfter(tab) ?? workspace.tabBefore(tab)
        workspace.closeTab(tab)
        if selectedTab === tab {
            selectedTab = next ?? workspace.addTerminal()
        }
    }
}
