import Foundation

struct GitBranchListing {
    var branches: [GitBranchInfo] = []
    var worktrees: [GitWorktreeInfo] = []
    var mergeTarget: String?
    var mergedWorktreePaths: Set<URL> = []

    func deletionUnavailableReason(for branch: GitBranchInfo) -> String? {
        if branch.isCurrent { return "Switch to another branch before deleting this one." }
        if let worktree = worktrees.first(where: { $0.branch == branch.name }) {
            return "This branch is checked out at \(worktree.path.path). Switch that worktree to another branch or remove the linked worktree first."
        }
        return nil
    }
}
