import SwiftUI

@Observable
final class AppState {
    var selectedSession: ClaudeSession?

    // Inspector state
    var showingInspector = true
    var selectedInspectorTab: InspectorTab = .files

    /// Bumped by Cmd+J; observed by SessionDetailView to toggle the editor panel.
    var panelToggleToken = UUID()
}
