import Foundation

@Observable
final class InspectorViewState {
    var selectedTab: InspectorTab = .files
    var fileTree = FileTreeInspectorState()
    var search = SearchInspectorState()
    var git = GitInspectorState()
    var commands = CommandsInspectorState()
}

@Observable
final class CommandsInspectorState {
    var runner = CommandRunner()
    var showAddSheet = false
}

@Observable
final class FileTreeInspectorState {
    var model = FileTreeModel()
    var selectedID: FileItem.ID?
    var expandedIDs: Set<String> = []
    var savedExpandedIDs: Set<String>?
}

@Observable
final class SearchInspectorState {
    var model = SearchInspectorModel()
    var expandedIDs: Set<UUID> = []
    var selectedID: UUID?
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
