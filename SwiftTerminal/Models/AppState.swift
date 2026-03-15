import SwiftUI

@Observable
final class AppState {
    var workspaces: [Workspace] = [] {
        didSet {
            configureWorkspacePersistence()
            persist()
        }
    }
    var selectedWorkspace: Workspace? {
        didSet {
            guard selectedWorkspace?.id != oldValue?.id else { return }
            selectedWorkspace?.selectedTab?.hasBellNotification = false
            persist()
        }
    }
    var tabToClose: TerminalTab?
    var showCloseConfirmation = false

    private let store: AppStateStore

    init(store: AppStateStore = .default) {
        self.store = store

        if let snapshot = store.load() {
            workspaces = snapshot.workspaces.map { workspaceSnapshot in
                Workspace(
                    id: workspaceSnapshot.id,
                    name: workspaceSnapshot.name,
                    tabs: workspaceSnapshot.tabs.map {
                        TerminalTab(
                            id: $0.id,
                            title: $0.title,
                            currentDirectory: $0.currentDirectory
                        )
                    },
                    selectedTabID: workspaceSnapshot.selectedTabID
                )
            }
            selectedWorkspace = workspaces.first { $0.id == snapshot.selectedWorkspaceID } ?? workspaces.first
        }

        configureWorkspacePersistence()
    }

    @discardableResult
    func addWorkspace(name: String? = nil) -> Workspace {
        let workspace = Workspace(name: name ?? "Workspace \(workspaces.count + 1)")
        workspace.addTab()
        workspaces.append(workspace)
        selectedWorkspace = workspace
        return workspace
    }

    func removeWorkspace(_ workspace: Workspace) {
        workspace.terminateAll()
        workspaces.removeAll { $0.id == workspace.id }
        if selectedWorkspace === workspace {
            selectedWorkspace = workspaces.first
        }
    }

    func closeSelectedTabWithConfirmation() {
        guard let selectedTab = selectedWorkspace?.selectedTab else { return }
        if selectedTab.isProcessActive {
            tabToClose = selectedTab
            showCloseConfirmation = true
        } else {
            selectedWorkspace?.closeSelectedTab()
        }
    }

    func confirmCloseTab() {
        if let tabToClose, let workspace = selectedWorkspace {
            workspace.closeTab(tabToClose)
        }
        tabToClose = nil
        showCloseConfirmation = false
    }

    func cancelCloseTab() {
        tabToClose = nil
        showCloseConfirmation = false
    }

    func persist() {
        store.save(
            AppStateSnapshot(
                workspaces: workspaces.map { workspace in
                    WorkspaceSnapshot(
                        id: workspace.id,
                        name: workspace.name,
                        tabs: workspace.tabs.map { tab in
                            TerminalTabSnapshot(
                                id: tab.id,
                                title: tab.title,
                                currentDirectory: tab.currentDirectory
                            )
                        },
                        selectedTabID: workspace.selectedTab?.id
                    )
                },
                selectedWorkspaceID: selectedWorkspace?.id
            )
        )
    }

    private func configureWorkspacePersistence() {
        for workspace in workspaces {
            workspace.onPersistChange = { [weak self] in
                self?.persist()
            }
        }
    }
}
