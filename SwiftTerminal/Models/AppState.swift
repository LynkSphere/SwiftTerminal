import SwiftUI

@Observable
final class AppState {
    var workspaces: [Workspace] = []
    var selectedWorkspace: Workspace?

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
}
