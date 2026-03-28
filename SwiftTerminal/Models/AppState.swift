import SwiftUI
import SwiftData

// MARK: - Sidebar Selection

enum SidebarSelection: Hashable {
    case workspace(UUID)
    case session(workspaceID: UUID, sessionID: String)

    var workspaceID: UUID {
        switch self {
        case .workspace(let id): id
        case .session(let id, _): id
        }
    }
}

// MARK: - App State

@Observable
final class AppState {
    var workspaces: [Workspace] = []
    var sidebarSelection: SidebarSelection?
    var tabToClose: TerminalTab?
    var showCloseConfirmation = false

    // Inspector state
    var showingInspector = true
    var selectedInspectorTab: InspectorTab = .files
    var searchFocusToken: UUID?
    var inspectorWidth: CGFloat = 0

    /// Bumped by Cmd+J; observed by WorkspaceDetailView to toggle the editor panel.
    var panelToggleToken = UUID()

    let modelContext: ModelContext

    /// Keeps ClaudeService instances alive across view changes.
    @ObservationIgnored private var serviceRegistry: [UUID: ClaudeService] = [:]

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        let descriptor = FetchDescriptor<Workspace>(sortBy: [SortDescriptor(\.sortOrder)])
        workspaces = (try? modelContext.fetch(descriptor)) ?? []
        sidebarSelection = workspaces.first.map { .workspace($0.id) }
    }

    // MARK: - Selection

    var selectedWorkspace: Workspace? {
        get {
            guard let sel = sidebarSelection else { return nil }
            return workspaces.first { $0.id == sel.workspaceID }
        }
        set {
            sidebarSelection = newValue.map { .workspace($0.id) }
        }
    }

    var selectedSessionID: String? {
        if case .session(_, let sid) = sidebarSelection {
            return sid
        }
        return nil
    }

    // MARK: - Claude Service Registry

    func claudeService(for workspace: Workspace) -> ClaudeService {
        if let existing = serviceRegistry[workspace.id] {
            return existing
        }
        let service = ClaudeService(workingDirectory: workspace.directory ?? NSHomeDirectory())
        serviceRegistry[workspace.id] = service
        return service
    }

    // MARK: - Workspace Management

    @discardableResult
    func addWorkspace(name: String? = nil, directory: String? = nil) -> Workspace {
        let resolvedName = name ?? directory.flatMap { URL(fileURLWithPath: $0).lastPathComponent } ?? "Workspace \(workspaces.count + 1)"
        let workspace = Workspace(name: resolvedName, directory: directory, sortOrder: workspaces.count)
        modelContext.insert(workspace)
        workspace.addTab(currentDirectory: directory)
        workspaces.append(workspace)
        sidebarSelection = .workspace(workspace.id)
        return workspace
    }

    func removeWorkspace(_ workspace: Workspace) {
        workspace.terminateAll()
        serviceRegistry[workspace.id]?.clearSession()
        serviceRegistry.removeValue(forKey: workspace.id)
        workspaces.removeAll { $0.id == workspace.id }
        modelContext.delete(workspace)
        if sidebarSelection?.workspaceID == workspace.id {
            sidebarSelection = workspaces.first.map { .workspace($0.id) }
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

    func newSession(for workspace: Workspace) {
        claudeService(for: workspace).clearSession()
        sidebarSelection = .workspace(workspace.id)
    }
}
