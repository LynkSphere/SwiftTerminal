import SwiftUI

@Observable
final class AppState {
    var selectedWorkspace: Workspace?
    var selectedChat: Chat? {
        didSet {
            oldValue?.hasNotification = false
            selectedChat?.hasNotification = false
        }
    }

    // Sidebar expansion state
    var expandedWorkspaceIDs: Set<String> = []

    // Inspector state
    var showingInspector = true
}
