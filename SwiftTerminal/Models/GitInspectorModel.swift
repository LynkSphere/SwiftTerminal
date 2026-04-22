import Foundation

enum SyncStrategy {
    case merge
    case rebase
}

@Observable @MainActor
final class GitInspectorModel {
    private(set) var snapshots: [GitRepositoryStatusSnapshot] = []
    private(set) var isLoading = false
    private(set) var activeTaskCount = 0
    var errorMessage: String?
    var successMessage: String?

    var isBusy: Bool { activeTaskCount > 0 }

    var hasChanges: Bool {
        snapshots.contains { !$0.stagedFiles.isEmpty || !$0.unstagedFiles.isEmpty }
    }

    func refresh(directoryURL: URL) async {
        isLoading = snapshots.isEmpty
        errorMessage = nil

        do {
            let newSnapshots = try await GitRepository.shared.statusSnapshots(in: directoryURL)
            if newSnapshots != snapshots {
                snapshots = newSnapshots
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func stage(files: [GitChangedFile], snapshot: GitRepositoryStatusSnapshot) async {
        let paths = files.map(\.repositoryRelativePath)
        guard !paths.isEmpty else { return }
        await perform {
            try await GitRepository.shared.stage(paths: paths, at: snapshot.repositoryRootURL)
        }
    }

    func unstage(files: [GitChangedFile], snapshot: GitRepositoryStatusSnapshot) async {
        let paths = files.map(\.repositoryRelativePath)
        guard !paths.isEmpty else { return }
        await perform {
            try await GitRepository.shared.unstage(paths: paths, at: snapshot.repositoryRootURL)
        }
    }

    func stageAll(snapshot: GitRepositoryStatusSnapshot) async {
        let paths = snapshot.unstagedFiles.map(\.repositoryRelativePath)
        guard !paths.isEmpty else { return }
        await perform {
            try await GitRepository.shared.stage(paths: paths, at: snapshot.repositoryRootURL)
        }
    }

    func unstageAll(snapshot: GitRepositoryStatusSnapshot) async {
        let paths = snapshot.stagedFiles.map(\.repositoryRelativePath)
        guard !paths.isEmpty else { return }
        await perform {
            try await GitRepository.shared.unstage(paths: paths, at: snapshot.repositoryRootURL)
        }
    }

    func discardChanges(files: [GitChangedFile], snapshot: GitRepositoryStatusSnapshot) async {
        let tracked = files.filter { $0.kind != .untracked }.map(\.repositoryRelativePath)
        let untracked = files.filter { $0.kind == .untracked }.map(\.repositoryRelativePath)
        await perform {
            try await GitRepository.shared.discardChanges(trackedPaths: tracked, untrackedPaths: untracked, at: snapshot.repositoryRootURL)
        }
    }

    func discardAllChanges(snapshot: GitRepositoryStatusSnapshot) async {
        await perform {
            try await GitRepository.shared.discardAllChanges(at: snapshot.repositoryRootURL)
        }
    }

    func commit(message: String, snapshot: GitRepositoryStatusSnapshot) async {
        await perform(successLabel: "Committed successfully") {
            try await GitRepository.shared.commit(message: message, at: snapshot.repositoryRootURL)
        }
    }

    func push(snapshot: GitRepositoryStatusSnapshot) async {
        await perform(successLabel: "Pushed successfully") {
            try await GitRepository.shared.push(at: snapshot.repositoryRootURL)
        }
    }

    func pushSetUpstream(branch: String, snapshot: GitRepositoryStatusSnapshot) async {
        await perform(successLabel: "Branch published successfully") {
            try await GitRepository.shared.pushSetUpstream(branch: branch, at: snapshot.repositoryRootURL)
        }
    }

    func remoteURL(snapshot: GitRepositoryStatusSnapshot) async -> String? {
        do {
            return try await GitRepository.shared.remoteURL(at: snapshot.repositoryRootURL)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func pull(snapshot: GitRepositoryStatusSnapshot) async {
        await perform(successLabel: "Pulled successfully") {
            try await GitRepository.shared.pull(at: snapshot.repositoryRootURL)
        }
    }

    func pullRebase(snapshot: GitRepositoryStatusSnapshot) async {
        await perform(successLabel: "Rebased with remote") {
            try await GitRepository.shared.pullRebase(at: snapshot.repositoryRootURL)
        }
    }

    func syncWithBaseBranch(using strategy: SyncStrategy, snapshot: GitRepositoryStatusSnapshot) async {
        guard let baseBranch = await GitRepository.shared.defaultBranch(at: snapshot.repositoryRootURL) else {
            errorMessage = "Could not determine the default branch."
            return
        }
        // Fetch first to ensure we have latest remote state
        try? await GitRepository.shared.fetch(at: snapshot.repositoryRootURL)
        let remoteBranch = "origin/\(baseBranch)"
        switch strategy {
        case .merge:
            await perform(successLabel: "Merged with \(baseBranch)") {
                try await GitRepository.shared.mergeBranch(remoteBranch, at: snapshot.repositoryRootURL)
            }
        case .rebase:
            await perform(successLabel: "Rebased onto \(baseBranch)") {
                try await GitRepository.shared.rebaseBranch(remoteBranch, at: snapshot.repositoryRootURL)
            }
        }
    }

    func syncWithRemote(using strategy: SyncStrategy, snapshot: GitRepositoryStatusSnapshot) async {
        // Fetch first to ensure we have latest remote state
        try? await GitRepository.shared.fetch(at: snapshot.repositoryRootURL)
        switch strategy {
        case .merge:
            await perform(successLabel: "Pulled from remote") {
                try await GitRepository.shared.pull(at: snapshot.repositoryRootURL)
            }
        case .rebase:
            await perform(successLabel: "Rebased with remote") {
                try await GitRepository.shared.pullRebase(at: snapshot.repositoryRootURL)
            }
        }
    }

    func fetch(snapshot: GitRepositoryStatusSnapshot) async {
        await perform {
            try await GitRepository.shared.fetch(at: snapshot.repositoryRootURL)
        }
    }

    func switchBranch(to branch: String, snapshot: GitRepositoryStatusSnapshot) async {
        await perform(successLabel: "Switched to \(branch)") {
            try await GitRepository.shared.switchBranch(to: branch, at: snapshot.repositoryRootURL)
        }
    }

    func createBranch(named name: String, snapshot: GitRepositoryStatusSnapshot) async {
        await perform(successLabel: "Created branch \(name)") {
            try await GitRepository.shared.createBranch(named: name, at: snapshot.repositoryRootURL)
        }
    }

    func stashAndSwitch(to branch: String, snapshot: GitRepositoryStatusSnapshot) async {
        let stashed = await perform {
            try await GitRepository.shared.stashAll(at: snapshot.repositoryRootURL)
        }
        guard stashed else { return }
        await perform {
            try await GitRepository.shared.switchBranch(to: branch, at: snapshot.repositoryRootURL)
        }
    }

    func stashAll(message: String, snapshot: GitRepositoryStatusSnapshot) async {
        await perform(successLabel: "Changes stashed") {
            try await GitRepository.shared.stashAll(message: message, at: snapshot.repositoryRootURL)
        }
    }

    func undoLastCommit(snapshot: GitRepositoryStatusSnapshot) async {
        await perform(successLabel: "Last commit undone") {
            try await GitRepository.shared.undoLastCommit(at: snapshot.repositoryRootURL)
        }
    }

    func amendCommitMessage(_ message: String, snapshot: GitRepositoryStatusSnapshot) async {
        await perform(successLabel: "Commit renamed") {
            try await GitRepository.shared.amendCommitMessage(message, at: snapshot.repositoryRootURL)
        }
    }

    func canApplyStashCleanly(snapshot: GitRepositoryStatusSnapshot) async -> Bool {
        await GitRepository.shared.canStashApplyCleanly(at: snapshot.repositoryRootURL)
    }

    func applyLatestStash(snapshot: GitRepositoryStatusSnapshot) async {
        await perform(successLabel: "Stash applied") {
            try await GitRepository.shared.stashPop(at: snapshot.repositoryRootURL)
        }
    }

    // MARK: - Private

    @discardableResult
    private func perform(successLabel: String? = nil, _ operation: () async throws -> Void) async -> Bool {
        activeTaskCount += 1
        defer { activeTaskCount -= 1 }
        errorMessage = nil
        successMessage = nil
        do {
            try await operation()
            if let successLabel {
                successMessage = successLabel
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
