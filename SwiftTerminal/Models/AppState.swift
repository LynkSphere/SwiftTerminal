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
}
