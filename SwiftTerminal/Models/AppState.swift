import SwiftUI

@Observable
final class AppState {
    var selectedWorkspace: Workspace?
    var selectedTerminal: Terminal?

    // Drives NavigationSplitView column visibility so we can toggle the
    // sidebar programmatically (e.g. when the bottom editor panel expands).
    var sidebarVisibility: NavigationSplitViewVisibility = .automatic

    // Inspector state
    var showingInspector = true

    // Close tab confirmation
    var terminalPendingClose: Terminal?

    // Whether archived workspaces are temporarily revealed in the sidebar.
    var showArchivedWorkspaces = false

    // Workspace whose scratch pad should be opened. WorkspaceDetailView watches
    // this and presents the sheet when its workspace matches.
    var scratchPadRequest: Workspace?

    // Set when the user invokes Run on a command that's already running.
    // ContentView shows a confirmation alert that interrupts then re-runs.
    var pendingRunReplacement: Terminal?

    // MARK: - Split panes

    /// Per-tab split layout, keyed by the tab's representative `Terminal.id`.
    /// Absent means an unsplit tab. Session-only; never persisted.
    var paneTrees: [UUID: PaneNode] = [:]

    var focusedPaneID: UUID?

    /// A pane awaiting close confirmation because it has a running child process.
    var panePendingClose: Terminal?
}
