import SwiftUI
import SwiftData

@Observable
final class AppState {
    var workspaces: [Workspace] = []
    var selectedWorkspace: Workspace?
    var tabToClose: TerminalTab?
    var showCloseConfirmation = false

    let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        let descriptor = FetchDescriptor<Workspace>(sortBy: [SortDescriptor(\.sortOrder)])
        workspaces = (try? modelContext.fetch(descriptor)) ?? []
        selectedWorkspace = workspaces.first
    }

    @discardableResult
    func addWorkspace(name: String? = nil, directory: String? = nil) -> Workspace {
        let resolvedName = name ?? directory.flatMap { URL(fileURLWithPath: $0).lastPathComponent } ?? "Workspace \(workspaces.count + 1)"
        let workspace = Workspace(name: resolvedName, directory: directory, sortOrder: workspaces.count)
        modelContext.insert(workspace)
        workspace.addTab(currentDirectory: directory)
        workspaces.append(workspace)
        selectedWorkspace = workspace
        return workspace
    }

    func removeWorkspace(_ workspace: Workspace) {
        workspace.terminateAll()
        workspaces.removeAll { $0.id == workspace.id }
        modelContext.delete(workspace)
        if selectedWorkspace === workspace {
            selectedWorkspace = workspaces.first
        }
    }

    func moveWorkspaces(from source: IndexSet, to destination: Int) {
        withAnimation {
            workspaces.move(fromOffsets: source, toOffset: destination)
            for (i, ws) in workspaces.enumerated() {
                ws.sortOrder = i
            }
        }
    }
}
