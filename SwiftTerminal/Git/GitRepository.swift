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
        var snapshots: [GitRepositoryStatusSnapshot] = []

        for repositoryRootURL in repositoryRootURLs {
            let entries = try await self.executor.execute(GitStatusCommand(), at: repositoryRootURL)
            let branchName = try? await self.executor.execute(GitBranchNameCommand(), at: repositoryRootURL)
            var stagedFiles: [GitChangedFile] = []
            var unstagedFiles: [GitChangedFile] = []

            for entry in entries {
                guard
                    let stagedKind = entry.stagedKind,
                    let fileURL = Self.fileURL(for: entry.path, in: repositoryRootURL, scopedTo: directoryURL)
                else { continue }

                stagedFiles.append(GitChangedFile(fileURL: fileURL, repositoryRelativePath: entry.path, kind: stagedKind))
            }

            for entry in entries {
                guard
                    let unstagedKind = entry.unstagedKind,
                    let fileURL = Self.fileURL(for: entry.path, in: repositoryRootURL, scopedTo: directoryURL)
                else { continue }

                unstagedFiles.append(GitChangedFile(fileURL: fileURL, repositoryRelativePath: entry.path, kind: unstagedKind))
            }

            snapshots.append(GitRepositoryStatusSnapshot(
                repositoryRootURL: repositoryRootURL,
                branchName: branchName,
                stagedFiles: stagedFiles,
                unstagedFiles: unstagedFiles
            ))
        }

        return snapshots
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
            let raw = try await self.executor.execute(
                GitGutterDiffCommand(relativePath: relativePath), at: rootURL)
            return GutterDiffParser.parse(raw)
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

    // MARK: - Private

    private func repositoryRoots(in directoryURL: URL) async -> [URL] {
        let directoryURL = directoryURL.standardizedFileURL.resolvingSymlinksInPath()
        var repositoryRootURLs: Set<URL> = []

        for candidateDirectoryURL in self.candidateDirectories(in: directoryURL) {
            do {
                let repositoryRootURL = try await self.executor.execute(GitRepositoryRootCommand(), at: candidateDirectoryURL)
                let resolvedRoot = repositoryRootURL.standardizedFileURL.resolvingSymlinksInPath()

                // Accept if: workspace is inside or equal to the repo root,
                // OR the repo root is inside the workspace (nested repo)
                guard resolvedRoot == directoryURL
                        || resolvedRoot.isAncestor(of: directoryURL)
                        || directoryURL.isAncestor(of: resolvedRoot)
                else { continue }

                repositoryRootURLs.insert(resolvedRoot)
            } catch {
                continue
            }
        }

        return repositoryRootURLs.sorted { $0.path < $1.path }
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
    var stagedFiles: [GitChangedFile]
    var unstagedFiles: [GitChangedFile]
}

struct GitChangedFile: Equatable, Hashable {
    var fileURL: URL
    var repositoryRelativePath: String
    var kind: GitChangeKind
}

enum GitChangeKind: String, Equatable, Hashable {
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

struct GitStatusCommand: GitCommand {
    var arguments: [String] {
        ["status", "--porcelain=v1", "-z", "--untracked-files=all"]
    }

    func parse(output: String) throws -> [GitStatusEntry] {
        GitStatusParser.parse(output)
    }
}

struct GitBranchNameCommand: GitCommand {
    var arguments: [String] {
        ["branch", "--show-current"]
    }

    func parse(output: String) throws -> String? {
        let name = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}

struct GitGutterDiffCommand: GitCommand {
    let relativePath: String

    var arguments: [String] {
        ["diff", "HEAD", "--no-color", "--no-ext-diff", "--unified=0", "--", relativePath]
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

// MARK: - Status Parser

enum GitStatusParser {
    static func parse(_ output: String) -> [GitStatusEntry] {
        guard !output.isEmpty else { return [] }

        let entries = output.split(separator: "\0", omittingEmptySubsequences: false)
        var results: [GitStatusEntry] = []
        var index = 0

        while index < entries.count {
            let entry = String(entries[index])
            guard entry.count >= 3 else { index += 1; continue }

            guard
                let indexStatus = GitStatusCode(rawValue: entry[entry.startIndex]),
                let workTreeStatus = GitStatusCode(rawValue: entry[entry.index(after: entry.startIndex)])
            else { index += 1; continue }

            let isRenamedOrCopied = [.renamed, .copied].contains(indexStatus) || [.renamed, .copied].contains(workTreeStatus)
            let path = String(entry.dropFirst(3))
            results.append(GitStatusEntry(path: path, indexStatus: indexStatus, workTreeStatus: workTreeStatus))
            index += isRenamedOrCopied ? 2 : 1
        }

        return results
    }
}
