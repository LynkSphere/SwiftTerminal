import Foundation

actor GitRepository {
    static let shared = GitRepository()

    private let executor = GitExecutor()

    func containsRepository(at directoryURL: URL) async -> Bool {
        await !self.repositoryRoots(in: directoryURL).isEmpty
    }

    func statusSnapshots(in directoryURL: URL) async throws -> [GitRepositoryStatusSnapshot] {
        let directoryURL = directoryURL.standardizedFileURL
        let repositoryRootURLs = await self.repositoryRoots(in: directoryURL)

        return try await withThrowingTaskGroup(of: GitRepositoryStatusSnapshot.self) { group in
            for repositoryRootURL in repositoryRootURLs {
                group.addTask {
                    var status = try await self.executor.execute(GitStatusCommand(), at: repositoryRootURL)

                    if !status.hasUpstream, let branchName = status.branchName {
                        let remoteRef = "origin/\(branchName)"
                        if let counts = try? await self.executor.execute(
                            GitAheadBehindAgainstRefCommand(remoteRef: remoteRef),
                            at: repositoryRootURL
                        ) {
                            status.hasUpstream = true
                            status.upstreamBranch = remoteRef
                            status.aheadCount = counts.ahead
                            status.behindCount = counts.behind
                        }
                    }

                    async let localBranches = (try? self.executor.execute(GitLocalBranchesCommand(), at: repositoryRootURL)) ?? []
                    async let unpushedCommits = self.fetchUnpushedCommits(
                        at: repositoryRootURL,
                        hasTrackingBranch: status.hasUpstream,
                        aheadCount: status.aheadCount,
                        branchName: status.branchName,
                        upstreamRef: status.upstreamBranch
                    )

                    var stagedFiles: [GitChangedFile] = []
                    var unstagedFiles: [GitChangedFile] = []

                    for entry in status.entries {
                        if let stagedKind = entry.stagedKind,
                           let fileURL = Self.fileURL(for: entry.path, in: repositoryRootURL, scopedTo: directoryURL) {
                            stagedFiles.append(GitChangedFile(fileURL: fileURL, repositoryRelativePath: entry.path, kind: stagedKind))
                        }
                        if let unstagedKind = entry.unstagedKind,
                           let fileURL = Self.fileURL(for: entry.path, in: repositoryRootURL, scopedTo: directoryURL) {
                            unstagedFiles.append(GitChangedFile(fileURL: fileURL, repositoryRelativePath: entry.path, kind: unstagedKind))
                        }
                    }

                    return GitRepositoryStatusSnapshot(
                        repositoryRootURL: repositoryRootURL,
                        branchName: status.branchName,
                        localBranches: await localBranches,
                        stagedFiles: stagedFiles,
                        unstagedFiles: unstagedFiles,
                        unpushedCommits: await unpushedCommits,
                        remoteAheadCount: status.behindCount,
                        hasTrackingBranch: status.hasUpstream
                    )
                }
            }

            var snapshots: [GitRepositoryStatusSnapshot] = []
            for try await snapshot in group {
                snapshots.append(snapshot)
            }
            return snapshots.sorted { $0.repositoryRootURL.path < $1.repositoryRootURL.path }
        }
    }

    func initializeRepository(at directoryURL: URL) async throws {
        try await self.executor.execute(GitInitCommand(), at: directoryURL)
    }

    func changedFileURLs(in directoryURL: URL) async throws -> Set<URL> {
        let snapshots = try await self.statusSnapshots(in: directoryURL)
        return Set(
            snapshots
                .flatMap { $0.stagedFiles + $0.unstagedFiles }
                .map { $0.fileURL.standardizedFileURL }
        )
    }

    func changedFileStatuses(in directoryURL: URL) async throws -> [URL: GitChangeKind] {
        let snapshots = try await self.statusSnapshots(in: directoryURL)
        var statuses: [URL: GitChangeKind] = [:]

        for snapshot in snapshots {
            for file in snapshot.unstagedFiles {
                statuses[file.fileURL.standardizedFileURL] = file.kind
            }
            for file in snapshot.stagedFiles {
                statuses[file.fileURL.standardizedFileURL] = file.kind
            }
        }

        return statuses
    }

    func gutterDiff(for fileURL: URL, in directoryURL: URL) async throws -> GutterDiffResult {
        let directoryURL = directoryURL.standardizedFileURL
        let fileURL = fileURL.standardizedFileURL
        let repositoryRootURLs = await self.repositoryRoots(in: directoryURL)

        for rootURL in repositoryRootURLs {
            let rootPath = rootURL.path(percentEncoded: false)
            let filePath = fileURL.path(percentEncoded: false)
            guard filePath.hasPrefix(rootPath) else { continue }

            let relativePath = String(filePath.dropFirst(rootPath.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            async let unstagedRaw = self.executor.execute(
                GitGutterDiffCommand(relativePath: relativePath, stage: .unstaged),
                at: rootURL
            )
            async let stagedRaw = self.executor.execute(
                GitGutterDiffCommand(relativePath: relativePath, stage: .staged),
                at: rootURL
            )
            let unstaged = GutterDiffParser.parse(try await unstagedRaw, stage: .unstaged)
            let staged = GutterDiffParser.parse(try await stagedRaw, stage: .staged)
            return GutterDiffParser.merge(unstaged: unstaged, staged: staged)
        }

        return .empty
    }

    func diffFilePresentation(for reference: GitDiffReference) async throws -> DiffFilePresentation {
        if reference.kind == .untracked {
            // For untracked files, generate a synthetic diff
            let pres = try self.presentationForUntrackedFile(reference)
            let raw = """
            diff --git a/\(reference.repositoryRelativePath) b/\(reference.repositoryRelativePath)
            new file mode 100644
            --- /dev/null
            +++ b/\(reference.repositoryRelativePath)
            """
            let lines = pres.string.split(separator: "\n", omittingEmptySubsequences: false)
            let hunkHeader = "@@ -0,0 +1,\(max(lines.count, 1)) @@"
            let hunkLines = lines.map { "+" + $0 }
            let fullRaw = raw + "\n" + hunkHeader + "\n" + hunkLines.joined(separator: "\n") + "\n"
            let fileHeader = raw
            return DiffFilePresentation(raw: fullRaw, fileHeader: fileHeader)
        }

        let raw = try await self.executor.execute(GitDiffCommand(reference: reference), at: reference.repositoryRootURL)
        guard !raw.isEmpty else {
            return DiffFilePresentation(message: "No diff available.")
        }

        // Extract file header (everything before first @@)
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var headerLines: [String] = []
        for line in lines {
            if line.hasPrefix("@@") { break }
            headerLines.append(line)
        }
        let fileHeader = headerLines.joined(separator: "\n")

        return DiffFilePresentation(raw: raw, fileHeader: fileHeader)
    }

    func applyPatch(_ patchText: String, reverse: Bool = false, cached: Bool = false, at repositoryRootURL: URL) async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".patch")
        try patchText.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try await self.executor.execute(
            GitApplyPatchCommand(patchFilePath: tempURL.path, reverse: reverse, cached: cached),
            at: repositoryRootURL
        )
    }

    func diffPresentation(for reference: GitDiffReference) async throws -> GitDiffPresentation {
        if reference.kind == .untracked {
            return try self.presentationForUntrackedFile(reference)
        }

        let raw = try await self.executor.execute(GitDiffCommand(reference: reference), at: reference.repositoryRootURL)
        guard !raw.isEmpty else {
            return GitDiffPresentation(message: "No diff available.")
        }
        return GitDiffPresentation(raw: raw)
    }

    func fullContextDiffPresentation(for reference: GitDiffReference) async throws -> GitDiffPresentation {
        if reference.kind == .untracked {
            return try self.presentationForUntrackedFile(reference)
        }

        let raw = try await self.executor.execute(
            GitFullContextDiffCommand(reference: reference),
            at: reference.repositoryRootURL
        )
        guard !raw.isEmpty else {
            return GitDiffPresentation(message: "No diff available.")
        }
        return GitDiffPresentation(raw: raw)
    }

    /// Returns the raw binary content of a file at a given git ref.
    /// - For unstaged diffs the "old" version lives in the index (`:path`).
    /// - For staged diffs the "old" version is HEAD (`HEAD:path`).
    /// - For commit diffs, the "old" is `commit^:path` and "new" is `commit:path`.
    func fileData(at relativePath: String, ref: String, repositoryRootURL: URL) async throws -> Data {
        try await self.executor.runRawData(
            arguments: ["show", "\(ref):\(relativePath)"],
            at: repositoryRootURL
        )
    }

    func stage(paths: [String], at repositoryRootURL: URL) async throws {
        try await self.executor.execute(GitStageCommand(paths: paths), at: repositoryRootURL)
    }

    func unstage(paths: [String], at repositoryRootURL: URL) async throws {
        try await self.executor.execute(GitUnstageCommand(paths: paths), at: repositoryRootURL)
    }

    func discardChanges(trackedPaths: [String], untrackedPaths: [String], at repositoryRootURL: URL) async throws {
        if !trackedPaths.isEmpty {
            try await self.executor.execute(GitDiscardCommand(paths: trackedPaths), at: repositoryRootURL)
        }
        if !untrackedPaths.isEmpty {
            try await self.executor.execute(GitCleanCommand(paths: untrackedPaths), at: repositoryRootURL)
        }
    }

    func discardAllChanges(at repositoryRootURL: URL) async throws {
        try await self.executor.execute(GitDiscardAllCommand(), at: repositoryRootURL)
        try await self.executor.execute(GitCleanUntrackedCommand(), at: repositoryRootURL)
    }

    func commit(message: String, at repositoryRootURL: URL) async throws {
        _ = try await self.executor.execute(GitCommitCommand(message: message), at: repositoryRootURL)
    }

    func push(at repositoryRootURL: URL) async throws {
        try await self.executor.execute(GitPushCommand(), at: repositoryRootURL)
    }

    func pushSetUpstream(branch: String, at repositoryRootURL: URL) async throws {
        try await self.executor.execute(GitPushSetUpstreamCommand(branch: branch), at: repositoryRootURL)
    }

    func remoteURL(at repositoryRootURL: URL) async throws -> String {
        try await self.executor.execute(GitRemoteURLCommand(), at: repositoryRootURL)
    }

    func pull(at repositoryRootURL: URL) async throws {
        try await self.executor.execute(GitPullCommand(), at: repositoryRootURL)
    }

    /// Pulls while preserving any staged/unstaged/untracked changes in the working tree.
    /// Stashes first, pulls, then re-applies. If re-apply would conflict, the working
    /// tree is rolled back exactly to its pre-pull state and `.wouldConflict` is returned.
    func pullPreservingChanges(at repositoryRootURL: URL) async throws -> PullPreservingResult {
        let originalHEAD = try await self.executor.execute(GitRevParseHeadCommand(), at: repositoryRootURL)

        try await self.executor.execute(GitStashCommand(), at: repositoryRootURL)

        do {
            try await self.executor.execute(GitPullCommand(), at: repositoryRootURL)
        } catch {
            try? await self.executor.execute(GitStashPopCommand(), at: repositoryRootURL)
            throw error
        }

        let applyResult = try await self.executor.runWithExitCode(
            arguments: ["stash", "apply", "--index"],
            at: repositoryRootURL
        )
        if applyResult.exitCode == 0 {
            try await self.executor.execute(GitStashDropCommand(), at: repositoryRootURL)
            return .clean
        }

        // Conflict: undo the pull and the partial apply, then restore the original tree.
        _ = try await self.executor.runWithExitCode(
            arguments: ["reset", "--hard", originalHEAD],
            at: repositoryRootURL
        )
        try await self.executor.execute(GitStashPopCommand(), at: repositoryRootURL)
        return .wouldConflict
    }

    func pullRebase(at repositoryRootURL: URL) async throws {
        try await self.executor.execute(GitPullRebaseCommand(), at: repositoryRootURL)
    }

    func rebaseBranch(_ branch: String, at repositoryRootURL: URL) async throws {
        try await self.executor.execute(GitRebaseBranchCommand(branch: branch), at: repositoryRootURL)
    }

    func fetch(at repositoryRootURL: URL) async throws {
        try await self.executor.execute(GitFetchCommand(), at: repositoryRootURL)
    }

    func commitLog(at repositoryRootURL: URL, limit: Int = 200) async throws -> [GitLogEntry] {
        try await self.executor.execute(GitLogCommand(limit: limit), at: repositoryRootURL)
    }

    func changedFiles(forCommit hash: String, at repositoryRootURL: URL) async throws -> [GitChangedFile] {
        let entries = try await self.executor.execute(GitCommitFilesCommand(hash: hash), at: repositoryRootURL)
        return entries.compactMap { entry in
            guard let kind = Self.changeKindFromDiffTreeStatus(entry.status) else { return nil }
            let fileURL = repositoryRootURL.appending(path: entry.path).standardizedFileURL
            return GitChangedFile(fileURL: fileURL, repositoryRelativePath: entry.path, kind: kind)
        }
    }

    func switchBranch(to branch: String, at repositoryRootURL: URL) async throws {
        try await self.executor.execute(GitSwitchCommand(branch: branch), at: repositoryRootURL)
    }

    func createBranch(named name: String, at repositoryRootURL: URL) async throws {
        try await self.executor.execute(GitCreateBranchCommand(name: name), at: repositoryRootURL)
    }

    func undoLastCommit(at repositoryRootURL: URL) async throws {
        try await self.executor.execute(GitResetSoftCommand(), at: repositoryRootURL)
    }

    func amendCommitMessage(_ message: String, at repositoryRootURL: URL) async throws {
        try await self.executor.execute(GitAmendMessageCommand(message: message), at: repositoryRootURL)
    }

    func stashAll(at repositoryRootURL: URL) async throws {
        try await self.executor.execute(GitStashCommand(), at: repositoryRootURL)
    }

    func stashAll(message: String, at repositoryRootURL: URL) async throws {
        try await self.executor.execute(GitStashWithMessageCommand(message: message), at: repositoryRootURL)
    }

    func canStashApplyCleanly(at repositoryRootURL: URL) async -> Bool {
        do {
            let diffData = try await self.executor.runRawData(
                arguments: ["stash", "show", "-p"],
                at: repositoryRootURL
            )
            let result = try await self.executor.run(
                arguments: ["apply", "--check"],
                stdinData: diffData,
                at: repositoryRootURL
            )
            return result.exitCode == 0
        } catch {
            return false
        }
    }

    func stashPop(at repositoryRootURL: URL) async throws {
        try await self.executor.execute(GitStashPopCommand(), at: repositoryRootURL)
    }

    // MARK: - Branch Management

    func localBranchesDetailed(at repositoryRootURL: URL) async throws -> [GitBranchInfo] {
        try await self._runBranchListDetailed(at: repositoryRootURL)
    }

    func deleteBranch(_ name: String, force: Bool, at repositoryRootURL: URL) async throws {
        try await self.executor.execute(GitDeleteBranchCommand(name: name, force: force), at: repositoryRootURL)
    }

    // MARK: - Stash Management

    func stashList(at repositoryRootURL: URL) async throws -> [GitStashEntry] {
        try await self.executor.execute(GitStashListCommand(), at: repositoryRootURL)
    }

    func dropStash(index: Int, at repositoryRootURL: URL) async throws {
        try await self.executor.execute(GitStashDropAtCommand(index: index), at: repositoryRootURL)
    }

    func applyStash(index: Int, at repositoryRootURL: URL) async throws {
        try await self.executor.execute(GitStashApplyAtCommand(index: index), at: repositoryRootURL)
    }

    func stashChangedFiles(index: Int, at repositoryRootURL: URL) async throws -> [GitChangedFile] {
        let entries = try await self.executor.execute(GitStashChangedFilesCommand(index: index), at: repositoryRootURL)
        return entries.compactMap { entry in
            guard let kind = Self.changeKindFromDiffTreeStatus(entry.status) else { return nil }
            let fileURL = repositoryRootURL.appending(path: entry.path).standardizedFileURL
            return GitChangedFile(fileURL: fileURL, repositoryRelativePath: entry.path, kind: kind)
        }
    }

    // MARK: - Private

    private func fetchUnpushedCommits(at repositoryRootURL: URL, hasTrackingBranch: Bool, aheadCount: Int, branchName: String?, upstreamRef: String? = nil) async -> [GitUnpushedCommit] {
        let commitEntries: [(hash: String, message: String)]
        if hasTrackingBranch {
            guard aheadCount > 0 else { return [] }
            let command = GitUnpushedCommitListCommand(upstreamRef: upstreamRef ?? "@{u}")
            guard let entries = try? await self.executor.execute(
                command, at: repositoryRootURL
            ) else { return [] }
            commitEntries = entries
        } else {
            guard let entries = try? await self.executor.execute(
                GitLocalOnlyCommitListCommand(branchName: branchName), at: repositoryRootURL
            ) else { return [] }
            commitEntries = entries
        }
        return commitEntries.map { GitUnpushedCommit(hash: $0.hash, message: $0.message) }
    }

    private nonisolated static func changeKindFromDiffTreeStatus(_ status: Character) -> GitChangeKind? {
        switch status {
            case "A": .added
            case "M": .modified
            case "D": .deleted
            case "R": .renamed
            case "C": .copied
            case "T": .typeChanged
            default: nil
        }
    }

    private func repositoryRoots(in directoryURL: URL) async -> [URL] {
        let directoryURL = directoryURL.standardizedFileURL.resolvingSymlinksInPath()
        let candidates = self.candidateDirectories(in: directoryURL)

        return await withTaskGroup(of: URL?.self) { group in
            for candidateDirectoryURL in candidates {
                group.addTask {
                    guard let repositoryRootURL = try? await self.executor.execute(
                        GitRepositoryRootCommand(), at: candidateDirectoryURL
                    ) else { return nil }

                    let resolvedRoot = repositoryRootURL.standardizedFileURL.resolvingSymlinksInPath()

                    // Accept if: workspace is inside or equal to the repo root,
                    // OR the repo root is inside the workspace (nested repo)
                    guard resolvedRoot == directoryURL
                            || resolvedRoot.isAncestor(of: directoryURL)
                            || directoryURL.isAncestor(of: resolvedRoot)
                    else { return nil }

                    return resolvedRoot
                }
            }

            var repositoryRootURLs: Set<URL> = []
            for await rootURL in group {
                if let rootURL { repositoryRootURLs.insert(rootURL) }
            }
            return repositoryRootURLs.sorted { $0.path < $1.path }
        }
    }

    private func candidateDirectories(in directoryURL: URL) -> [URL] {
        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .isHiddenKey]

        let childDirectoryURLs = (try? FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: Array(resourceKeys)))?
            .filter {
                guard let values = try? $0.resourceValues(forKeys: resourceKeys) else { return false }
                return values.isDirectory == true && values.isPackage != true && values.isHidden != true
            } ?? []

        return [directoryURL] + childDirectoryURLs
    }

    private func presentationForUntrackedFile(_ reference: GitDiffReference) throws -> GitDiffPresentation {
        let data = try Data(contentsOf: reference.fileURL)
        guard let string = String(data: data, encoding: .utf8) else {
            return GitDiffPresentation(message: "Binary diff preview is unavailable.")
        }

        let lines = string.split(separator: "\n", omittingEmptySubsequences: false)
        let lineCount = max(lines.count, 1)
        let hunkLines = lines.map { "+" + $0 }
        let raw = """
        diff --git a/\(reference.repositoryRelativePath) b/\(reference.repositoryRelativePath)
        new file mode 100644
        --- /dev/null
        +++ b/\(reference.repositoryRelativePath)
        @@ -0,0 +1,\(lineCount) @@
        \(hunkLines.joined(separator: "\n"))
        """
        return GitDiffPresentation(raw: raw)
    }

    private nonisolated static func fileURL(for path: String, in repositoryRootURL: URL, scopedTo directoryURL: URL) -> URL? {
        let fileURL = repositoryRootURL.appending(path: path).standardizedFileURL
        let resolvedDir = directoryURL.standardizedFileURL.resolvingSymlinksInPath()
        let resolvedFile = fileURL.resolvingSymlinksInPath()

        guard resolvedFile == resolvedDir || resolvedDir.isAncestor(of: resolvedFile) else { return nil }

        // Return the non-resolved URL so it matches FileItem URLs built from the original directory
        return fileURL
    }
}

// MARK: - URL Extension

extension URL {
    func isAncestor(of url: URL) -> Bool {
        let ancestorComponents = self.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let childComponents = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard ancestorComponents.count < childComponents.count else { return false }
        return zip(ancestorComponents, childComponents).allSatisfy(==)
    }
}

// MARK: - Git Repository Root Command

private struct GitRepositoryRootCommand: GitCommand {
    var arguments: [String] {
        ["rev-parse", "--show-toplevel"]
    }

    func parse(output: String) throws -> URL {
        URL(filePath: output.trimmingCharacters(in: .whitespacesAndNewlines), directoryHint: .isDirectory)
    }
}

// MARK: - Data Types

struct GitRepositoryStatusSnapshot: Equatable {
    var repositoryRootURL: URL
    var branchName: String?
    var localBranches: [String]
    var stagedFiles: [GitChangedFile]
    var unstagedFiles: [GitChangedFile]
    var unpushedCommits: [GitUnpushedCommit]
    var remoteAheadCount: Int
    var hasTrackingBranch: Bool

    var isDirty: Bool {
        !stagedFiles.isEmpty || !unstagedFiles.isEmpty
    }
}

struct GitUnpushedCommit: Equatable, Identifiable {
    var id: String { hash }
    var hash: String
    var message: String
}

struct GitLogEntry: Equatable, Identifiable, Sendable {
    var id: String { hash }
    var hash: String
    var shortHash: String
    var author: String
    var date: Date?
    var subject: String
}

struct GitBranchInfo: Equatable, Hashable, Identifiable {
    var name: String
    var isCurrent: Bool
    var isMerged: Bool
    var upstream: String?
    var id: String { name }
}

struct GitStashEntry: Equatable, Hashable, Identifiable {
    var index: Int
    var hash: String
    var branch: String?
    var message: String
    var date: Date?
    var id: String { hash }
}

struct GitChangedFile: Equatable, Hashable {
    var fileURL: URL
    var repositoryRelativePath: String
    var kind: GitChangeKind
}

enum GitChangeKind: String, Equatable, Hashable, Codable {
    case added
    case modified
    case deleted
    case renamed
    case copied
    case untracked
    case typeChanged
    case conflicted

    var statusSymbol: String {
        switch self {
            case .added: "A"
            case .modified: "M"
            case .deleted: "D"
            case .renamed: "R"
            case .copied: "C"
            case .untracked: "A"
            case .typeChanged: "T"
            case .conflicted: "U"
        }
    }
}

// MARK: - Status Parsing

struct GitStatusEntry: Equatable {
    var path: String
    var indexStatus: GitStatusCode
    var workTreeStatus: GitStatusCode

    var stagedKind: GitChangeKind? {
        self.indexStatus.changeKind(isStaged: true)
    }

    var unstagedKind: GitChangeKind? {
        self.workTreeStatus.changeKind(isStaged: false)
    }
}

enum GitStatusCode: Character, Equatable {
    case unmodified = " "
    case modified = "M"
    case added = "A"
    case deleted = "D"
    case renamed = "R"
    case copied = "C"
    case updatedButUnmerged = "U"
    case untracked = "?"
    case ignored = "!"
    case typeChanged = "T"

    func changeKind(isStaged: Bool) -> GitChangeKind? {
        switch self {
            case .unmodified, .ignored: nil
            case .modified: .modified
            case .added: .added
            case .deleted: .deleted
            case .renamed: .renamed
            case .copied: .copied
            case .updatedButUnmerged: .conflicted
            case .untracked: isStaged ? nil : .untracked
            case .typeChanged: .typeChanged
        }
    }
}

// MARK: - Git Commands

struct GitStatusResult: Equatable {
    var branchName: String?
    var upstreamBranch: String?
    var hasUpstream: Bool = false
    var aheadCount: Int = 0
    var behindCount: Int = 0
    var entries: [GitStatusEntry] = []
}

struct GitStatusCommand: GitCommand {
    var arguments: [String] {
        ["status", "--branch", "--porcelain=v2", "-z", "--untracked-files=all"]
    }

    func parse(output: String) throws -> GitStatusResult {
        GitStatusParser.parse(output)
    }
}

struct GitGutterDiffCommand: GitCommand {
    let relativePath: String
    let stage: GutterHunkStage

    var arguments: [String] {
        switch stage {
        case .staged:
            ["diff", "--cached", "--no-color", "--no-ext-diff", "--unified=0", "--", relativePath]
        case .unstaged:
            ["diff", "--no-color", "--no-ext-diff", "--unified=0", "--", relativePath]
        }
    }

    func parse(output: String) throws -> String { output }
}

struct GitStageCommand: GitCommand {
    let paths: [String]
    var arguments: [String] { ["add", "--"] + paths }
    func parse(output: String) throws { }
}

struct GitUnstageCommand: GitCommand {
    let paths: [String]
    var arguments: [String] { ["reset", "HEAD", "--"] + paths }
    func parse(output: String) throws { }
}

struct GitDiscardCommand: GitCommand {
    let paths: [String]
    var arguments: [String] { ["checkout", "--"] + paths }
    func parse(output: String) throws { }
}

struct GitCleanCommand: GitCommand {
    let paths: [String]
    var arguments: [String] { ["clean", "-f", "--"] + paths }
    func parse(output: String) throws { }
}

struct GitDiscardAllCommand: GitCommand {
    var arguments: [String] { ["checkout", "--", "."] }
    func parse(output: String) throws { }
}

struct GitCleanUntrackedCommand: GitCommand {
    var arguments: [String] { ["clean", "-fd"] }
    func parse(output: String) throws { }
}

struct GitApplyPatchCommand: GitCommand {
    let patchFilePath: String
    let reverse: Bool
    let cached: Bool

    var arguments: [String] {
        var args = ["apply"]
        if reverse { args.append("--reverse") }
        if cached { args.append("--cached") }
        args.append("--unidiff-zero")
        args.append(patchFilePath)
        return args
    }

    func parse(output: String) throws {}
}

struct GitCommitCommand: GitCommand {
    let message: String
    var arguments: [String] { ["commit", "-m", message] }
    func parse(output: String) throws -> String { output }
}

private struct GitInitCommand: GitCommand {
    var arguments: [String] { ["init"] }
    func parse(output: String) throws { }
}

struct GitPushCommand: GitCommand {
    var arguments: [String] { ["push"] }
    func parse(output: String) throws { }
}

private struct GitPushSetUpstreamCommand: GitCommand {
    let branch: String
    var arguments: [String] { ["push", "--set-upstream", "origin", branch] }
    func parse(output: String) throws { }
}

private struct GitRemoteURLCommand: GitCommand {
    var arguments: [String] { ["remote", "get-url", "origin"] }
    func parse(output: String) throws -> String {
        output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct GitPullCommand: GitCommand {
    var arguments: [String] { ["pull"] }
    func parse(output: String) throws { }
}

private struct GitPullRebaseCommand: GitCommand {
    var arguments: [String] { ["pull", "--rebase"] }
    func parse(output: String) throws { }
}

private struct GitRebaseBranchCommand: GitCommand {
    let branch: String
    var arguments: [String] { ["rebase", branch] }
    func parse(output: String) throws { }
}

struct GitFetchCommand: GitCommand {
    var arguments: [String] { ["fetch", "--all"] }
    func parse(output: String) throws { }
}

private struct GitLocalBranchesCommand: GitCommand {
    var arguments: [String] {
        ["branch", "--format=%(refname:short)"]
    }

    func parse(output: String) throws -> [String] {
        output.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

private struct GitSwitchCommand: GitCommand {
    let branch: String
    var arguments: [String] { ["switch", branch] }
    func parse(output: String) throws { }
}

private struct GitCreateBranchCommand: GitCommand {
    let name: String
    var arguments: [String] { ["switch", "-c", name, "--no-track"] }
    func parse(output: String) throws { }
}

private struct GitResetSoftCommand: GitCommand {
    var arguments: [String] { ["reset", "--soft", "HEAD~1"] }
    func parse(output: String) throws { }
}

private struct GitAmendMessageCommand: GitCommand {
    let message: String
    var arguments: [String] { ["commit", "--amend", "-m", message] }
    func parse(output: String) throws { }
}

private struct GitStashCommand: GitCommand {
    var arguments: [String] { ["stash", "--include-untracked"] }
    func parse(output: String) throws { }
}

private struct GitStashWithMessageCommand: GitCommand {
    let message: String
    var arguments: [String] { ["stash", "push", "--include-untracked", "-m", message] }
    func parse(output: String) throws { }
}

private struct GitStashPopCommand: GitCommand {
    var arguments: [String] { ["stash", "pop", "--index"] }
    func parse(output: String) throws { }
}

private struct GitStashDropCommand: GitCommand {
    var arguments: [String] { ["stash", "drop"] }
    func parse(output: String) throws { }
}

private struct GitRevParseHeadCommand: GitCommand {
    var arguments: [String] { ["rev-parse", "HEAD"] }
    func parse(output: String) throws -> String {
        output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct GitAheadBehindAgainstRefCommand: GitCommand {
    let remoteRef: String
    var arguments: [String] {
        ["rev-list", "--left-right", "--count", "HEAD...\(remoteRef)"]
    }

    func parse(output: String) throws -> (ahead: Int, behind: Int) {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count == 2,
              let ahead = Int(parts[0]),
              let behind = Int(parts[1]) else {
            return (0, 0)
        }
        return (ahead, behind)
    }
}

enum PullPreservingResult: Equatable, Sendable {
    case clean
    case wouldConflict
}

private struct GitUnpushedCommitListCommand: GitCommand {
    var upstreamRef: String = "@{u}"
    var arguments: [String] {
        ["log", "\(upstreamRef)..HEAD", "--pretty=format:%H%x00%s"]
    }

    func parse(output: String) throws -> [(hash: String, message: String)] {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return trimmed.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let parts = line.split(separator: "\0", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return (hash: String(parts[0]), message: String(parts[1]))
        }
    }
}

private struct GitLocalOnlyCommitListCommand: GitCommand {
    var branchName: String?

    var arguments: [String] {
        var args = ["log", "HEAD", "--not"]
        if let branchName {
            args += ["--exclude=\(branchName)", "--branches"]
        }
        args += ["--remotes", "--pretty=format:%H%x00%s"]
        return args
    }

    func parse(output: String) throws -> [(hash: String, message: String)] {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return trimmed.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let parts = line.split(separator: "\0", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return (hash: String(parts[0]), message: String(parts[1]))
        }
    }
}

private struct GitLogCommand: GitCommand {
    let limit: Int

    var arguments: [String] {
        [
            "log",
            "-n", String(limit),
            "--pretty=format:%H%x1f%h%x1f%an%x1f%aI%x1f%s",
        ]
    }

    func parse(output: String) throws -> [GitLogEntry] {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]

        return trimmed.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let parts = line.split(separator: "\u{1f}", maxSplits: 4, omittingEmptySubsequences: false)
            guard parts.count == 5 else { return nil }
            let dateString = String(parts[3])
            let date = formatter.date(from: dateString) ?? fallbackFormatter.date(from: dateString)
            return GitLogEntry(
                hash: String(parts[0]),
                shortHash: String(parts[1]),
                author: String(parts[2]),
                date: date,
                subject: String(parts[4])
            )
        }
    }
}

private struct GitCommitFilesCommand: GitCommand {
    let hash: String

    var arguments: [String] {
        ["diff-tree", "--no-commit-id", "-r", "--name-status", hash]
    }

    func parse(output: String) throws -> [(status: Character, path: String)] {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return trimmed.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let parts = line.split(separator: "\t")
            guard parts.count >= 2, let status = parts[0].first else { return nil }
            let path = String(parts.last!)
            return (status: status, path: path)
        }
    }
}

extension GitRepository {
    fileprivate func _runBranchListDetailed(at repositoryRootURL: URL) async throws -> [GitBranchInfo] {
        async let allRaw = self.executor.execute(GitAllBranchesRawCommand(), at: repositoryRootURL)
        async let mergedRaw = self.executor.execute(GitMergedBranchesRawCommand(), at: repositoryRootURL)
        let all = try await allRaw
        let merged = Set(try await mergedRaw)
        return all.map { GitBranchInfo(name: $0.name, isCurrent: $0.isCurrent, isMerged: merged.contains($0.name), upstream: $0.upstream) }
    }
}

private struct GitAllBranchesRawCommand: GitCommand {
    var arguments: [String] {
        ["branch", "--list", "--format=%(HEAD)%00%(refname:short)%00%(upstream:short)"]
    }

    func parse(output: String) throws -> [(name: String, isCurrent: Bool, upstream: String?)] {
        output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let parts = line.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 2 else { return nil }
            let isCurrent = parts[0].trimmingCharacters(in: .whitespaces) == "*"
            let name = parts[1].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            let upstream = parts.count >= 3 && !parts[2].isEmpty ? parts[2] : nil
            return (name, isCurrent, upstream)
        }
    }
}

private struct GitMergedBranchesRawCommand: GitCommand {
    var arguments: [String] {
        ["branch", "--list", "--merged", "HEAD", "--format=%(refname:short)"]
    }

    func parse(output: String) throws -> [String] {
        output.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

private struct GitDeleteBranchCommand: GitCommand {
    let name: String
    let force: Bool
    var arguments: [String] {
        ["branch", force ? "-D" : "-d", name]
    }
    func parse(output: String) throws { }
}

private struct GitStashListCommand: GitCommand {
    var arguments: [String] {
        // %gd → stash@{N}, %H full hash, %gs reflog subject, %aI iso date
        ["stash", "list", "--format=%gd%x1f%H%x1f%gs%x1f%aI"]
    }

    func parse(output: String) throws -> [GitStashEntry] {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]

        return trimmed.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let parts = line.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 4 else { return nil }
            let ref = parts[0]
            // ref looks like "stash@{3}"
            guard let openIdx = ref.firstIndex(of: "{"), let closeIdx = ref.firstIndex(of: "}") else { return nil }
            let indexString = ref[ref.index(after: openIdx)..<closeIdx]
            guard let index = Int(indexString) else { return nil }
            let hash = parts[1]
            let reflogSubject = parts[2]
            // reflogSubject typical: "WIP on main: abcdef1 commit message" or "On main: My message"
            var branch: String?
            var message = reflogSubject
            if let colonIdx = reflogSubject.firstIndex(of: ":") {
                let head = String(reflogSubject[..<colonIdx])
                let tail = reflogSubject[reflogSubject.index(after: colonIdx)...].trimmingCharacters(in: .whitespaces)
                if head.hasPrefix("WIP on ") {
                    branch = String(head.dropFirst("WIP on ".count))
                } else if head.hasPrefix("On ") {
                    branch = String(head.dropFirst("On ".count))
                }
                message = tail
            }
            let date = formatter.date(from: parts[3]) ?? fallbackFormatter.date(from: parts[3])
            return GitStashEntry(index: index, hash: hash, branch: branch, message: message, date: date)
        }
    }
}

private struct GitStashDropAtCommand: GitCommand {
    let index: Int
    var arguments: [String] { ["stash", "drop", "stash@{\(index)}"] }
    func parse(output: String) throws { }
}

private struct GitStashApplyAtCommand: GitCommand {
    let index: Int
    var arguments: [String] { ["stash", "apply", "--index", "stash@{\(index)}"] }
    func parse(output: String) throws { }
}

private struct GitStashChangedFilesCommand: GitCommand {
    let index: Int
    var arguments: [String] {
        ["stash", "show", "--name-status", "stash@{\(index)}"]
    }

    func parse(output: String) throws -> [(status: Character, path: String)] {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return trimmed.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let parts = line.split(separator: "\t")
            guard parts.count >= 2, let status = parts[0].first else { return nil }
            let path = String(parts.last!)
            return (status: status, path: path)
        }
    }
}

// MARK: - Status Parser

/// Parses `git status --branch --porcelain=v2 -z` output.
/// Each NUL-separated token is either a `# ...` header or a status entry whose
/// first character indicates type (`1`, `2`, `u`, `?`, `!`). Type `2` (rename/copy)
/// is followed by an extra NUL-separated token holding the original path.
enum GitStatusParser {
    static func parse(_ output: String) -> GitStatusResult {
        var result = GitStatusResult()
        guard !output.isEmpty else { return result }

        let tokens = output.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
        var i = 0
        while i < tokens.count {
            let token = tokens[i]
            if token.isEmpty { i += 1; continue }

            if token.hasPrefix("# ") {
                parseHeader(String(token.dropFirst(2)), into: &result)
                i += 1
                continue
            }

            guard let kind = token.first else { i += 1; continue }
            switch kind {
            case "1":
                if let entry = parseEntry(token, fieldsBeforePath: 8) {
                    result.entries.append(entry)
                }
                i += 1
            case "2":
                if let entry = parseEntry(token, fieldsBeforePath: 9) {
                    result.entries.append(entry)
                }
                i += 2
            case "u":
                if let entry = parseEntry(token, fieldsBeforePath: 10) {
                    result.entries.append(entry)
                }
                i += 1
            case "?":
                let path = String(token.dropFirst(2))
                result.entries.append(GitStatusEntry(path: path, indexStatus: .untracked, workTreeStatus: .untracked))
                i += 1
            default:
                i += 1
            }
        }

        return result
    }

    private static func parseHeader(_ body: String, into result: inout GitStatusResult) {
        if let value = stripPrefix(body, "branch.head ") {
            result.branchName = value == "(detached)" ? nil : value
        } else if let value = stripPrefix(body, "branch.upstream ") {
            result.upstreamBranch = value
            result.hasUpstream = true
        } else if let value = stripPrefix(body, "branch.ab ") {
            let parts = value.split(separator: " ")
            guard parts.count == 2 else { return }
            result.aheadCount = Int(parts[0].dropFirst()) ?? 0
            result.behindCount = Int(parts[1].dropFirst()) ?? 0
        }
    }

    private static func stripPrefix(_ string: String, _ prefix: String) -> String? {
        guard string.hasPrefix(prefix) else { return nil }
        return String(string.dropFirst(prefix.count))
    }

    private static func parseEntry(_ token: String, fieldsBeforePath: Int) -> GitStatusEntry? {
        guard token.count > 4 else { return nil }
        let xyStart = token.index(token.startIndex, offsetBy: 2)
        let yIndex = token.index(after: xyStart)
        // v2 uses "." for unmodified where v1 used " ".
        let xChar: Character = token[xyStart] == "." ? " " : token[xyStart]
        let yChar: Character = token[yIndex] == "." ? " " : token[yIndex]
        guard
            let indexStatus = GitStatusCode(rawValue: xChar),
            let workTreeStatus = GitStatusCode(rawValue: yChar)
        else { return nil }

        var spaceCount = 0
        var pathStart: String.Index?
        for index in token.indices where token[index] == " " {
            spaceCount += 1
            if spaceCount == fieldsBeforePath {
                pathStart = token.index(after: index)
                break
            }
        }
        guard let start = pathStart else { return nil }
        return GitStatusEntry(path: String(token[start...]), indexStatus: indexStatus, workTreeStatus: workTreeStatus)
    }
}
