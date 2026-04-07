import Foundation

@Observable
final class InspectorViewState {
    var selectedTab: InspectorTab = .files
    var fileTree = FileTreeInspectorState()
    var search = SearchInspectorState()
    var git = GitInspectorState()

    func revealInFileTree(_ url: URL, relativeTo rootURL: URL) {
        // Expand all ancestor folders
        var parent = url.deletingLastPathComponent()
        while parent.path.hasPrefix(rootURL.path) && parent != rootURL {
            fileTree.expandedIDs.insert(parent.path)
            parent = parent.deletingLastPathComponent()
        }
        selectedTab = .files
        // Delay selection so the FileTreeView's List is rendered first
        DispatchQueue.main.async { [self] in
            fileTree.selectedID = url.path
        }
    }
}

@Observable
final class FileTreeInspectorState {
    var model = FileTreeModel()
    var selectedID: FileItem.ID?
    var expandedIDs: Set<String> = []
    var savedExpandedIDs: Set<String>?
    var searchFocusTrigger = 0
    var renamingID: String?
}

@Observable
final class SearchInspectorState {
    var model = SearchInspectorModel()
    var expandedIDs: Set<String> = []
    var selectedID: String?
    var searchFocusTrigger = 0
}

enum GitInspectorDiscardTarget {
    case files([GitChangedFile], GitRepositoryStatusSnapshot)
    case all(GitRepositoryStatusSnapshot)
}

@Observable
final class GitInspectorState {
    var model = GitInspectorModel()
    var selectedRepoURL: URL?
    var selectedFileID: String?
    var commitMessage = ""
    var discardTarget: GitInspectorDiscardTarget?
    var pendingBranchSwitch: String?
    var showNewBranchSheet = false
    var newBranchName = ""
    var showStashAlert = false
    var stashMessage = ""
    var stagedExpanded = true
    var unstagedExpanded = true
}
