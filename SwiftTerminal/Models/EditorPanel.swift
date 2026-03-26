import Foundation

/// What the bottom editor panel should display.
enum EditorPanelContent {
    case file(URL)
    case diff(GitDiffReference)
}

/// Shared state for the bottom slide-up editor panel in the workspace.
@Observable
final class EditorPanel {
    var content: EditorPanelContent?
    var isDirty = false

    /// Pending content waiting for user confirmation to discard unsaved changes.
    var pendingContent: EditorPanelContent?

    var isOpen: Bool { content != nil }
    var showUnsavedAlert: Bool { pendingContent != nil }

    func openFile(_ url: URL) {
        setContent(.file(url))
    }

    func openDiff(_ reference: GitDiffReference) {
        setContent(.diff(reference))
    }

    func close() {
        if isDirty {
            pendingContent = content // sentinel: pending == current means close
            // The view will show the alert
        } else {
            forceClose()
        }
    }

    func confirmDiscard() {
        let pending = pendingContent
        pendingContent = nil
        isDirty = false

        if let pending {
            // Check if pending == current content (means user wanted to close)
            if isSameAsCurrent(pending) {
                content = nil
            } else {
                content = pending
            }
        }
    }

    func cancelDiscard() {
        pendingContent = nil
    }

    func forceClose() {
        isDirty = false
        pendingContent = nil
        content = nil
    }

    // MARK: - Private

    private func setContent(_ newContent: EditorPanelContent) {
        if isDirty {
            pendingContent = newContent
        } else {
            content = newContent
        }
    }

    private func isSameAsCurrent(_ other: EditorPanelContent) -> Bool {
        switch (content, other) {
        case (.file(let a), .file(let b)): return a == b
        case (.diff(let a), .diff(let b)): return a == b
        default: return false
        }
    }
}
