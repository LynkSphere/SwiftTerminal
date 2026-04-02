import SwiftUI

@Observable
final class AppState {
    var selectedWorkspace: Workspace?
    var selectedTerminal: Terminal?

    // Inspector state
    var showingInspector = true

    // Close tab confirmation
    var terminalPendingClose: Terminal?
}
