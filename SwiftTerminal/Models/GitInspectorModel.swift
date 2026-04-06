import Foundation

@Observable
final class GitInspectorModel {
    private(set) var snapshots: [GitRepositoryStatusSnapshot] = []
    private(set) var isLoading = false
    var errorMessage: String?

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
        await perform {
            try await GitRepository.shared.commit(message: message, at: snapshot.repositoryRootURL)
        }
    }

    func push(snapshot: GitRepositoryStatusSnapshot) async {
        await perform {
            try await GitRepository.shared.push(at: snapshot.repositoryRootURL)
        }
    }

    func pull(snapshot: GitRepositoryStatusSnapshot) async {
        await perform {
            try await GitRepository.shared.pull(at: snapshot.repositoryRootURL)
        }
    }

    func fetch(snapshot: GitRepositoryStatusSnapshot) async {
        await perform {
            try await GitRepository.shared.fetch(at: snapshot.repositoryRootURL)
        }
    }

    func switchBranch(to branch: String, snapshot: GitRepositoryStatusSnapshot) async {
        await perform {
            try await GitRepository.shared.switchBranch(to: branch, at: snapshot.repositoryRootURL)
        }
    }

    func createBranch(named name: String, snapshot: GitRepositoryStatusSnapshot) async {
        await perform {
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
        await perform {
            try await GitRepository.shared.stashAll(message: message, at: snapshot.repositoryRootURL)
        }
    }

    func applyLatestStash(snapshot: GitRepositoryStatusSnapshot) async {
        await perform {
            try await GitRepository.shared.stashPop(at: snapshot.repositoryRootURL)
        }
    }

    // MARK: - Private

    @discardableResult
    private func perform(_ operation: () async throws -> Void) async -> Bool {
        errorMessage = nil
        do {
            try await operation()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
