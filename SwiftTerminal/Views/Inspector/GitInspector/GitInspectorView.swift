import SwiftUI
import UniformTypeIdentifiers

struct GitInspectorView: View {
    let directoryURL: URL

    @Environment(EditorPanel.self) private var editorPanel
    @State private var model = GitInspectorModel()
    @State private var expandedRepos: Set<URL> = []
    @State private var selectedFileID: String?
    @State private var showCommitSheet = false
    @State private var commitMessage = ""
    @State private var discardTarget: DiscardTarget?

    var body: some View {
        changesList
            .overlay {
                if model.isLoading && model.snapshots.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .task(id: directoryURL) {
                await model.refresh(directoryURL: directoryURL)
                expandAllRepos()
            }
            .task(id: directoryURL, priority: .low) {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { break }
                    await model.refresh(directoryURL: directoryURL)
                }
            }
            .sheet(isPresented: $showCommitSheet) {
                GitCommitSheet(message: $commitMessage, isPresented: $showCommitSheet) { msg in
                    guard let snapshot = model.snapshots.first(where: { !$0.stagedFiles.isEmpty }) else { return }
                    Task {
                        await model.commit(message: msg, snapshot: snapshot)
                        await model.refresh(directoryURL: directoryURL)
                    }
                }
            }
            .alert("Discard Changes?", isPresented: discardAlertBinding) {
                Button("Discard", role: .destructive) {
                    guard let target = discardTarget else { return }
                    Task {
                        await performDiscard(target)
                        await model.refresh(directoryURL: directoryURL)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(discardAlertMessage)
            }
            .onChange(of: selectedFileID) { _, newID in
                guard let id = newID else { return }
                guard let (file, staged, snapshot) = resolveFile(id: id) else { return }
                editorPanel.openDiff(GitDiffReference(
                    repositoryRootURL: snapshot.repositoryRootURL,
                    fileURL: file.fileURL,
                    repositoryRelativePath: file.repositoryRelativePath,
                    stage: staged ? .staged : .unstaged,
                    kind: file.kind
                ))
            }
    }

    // MARK: - List

    private var changesList: some View {
        List(selection: $selectedFileID) {
            ForEach(model.snapshots, id: \.repositoryRootURL) { snapshot in
                DisclosureGroup(isExpanded: repoBinding(snapshot.repositoryRootURL)) {
                    fileRows(snapshot.stagedFiles, staged: true, snapshot: snapshot)
                    fileRows(snapshot.unstagedFiles, staged: false, snapshot: snapshot)
                } label: {
                    repoHeader(snapshot)
                        .contextMenu { GitRepoContextMenu(snapshot: snapshot, onAction: handleAction) }
                }
            }
            .listRowSeparator(.hidden)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Repo Header

    private func repoHeader(_ snapshot: GitRepositoryStatusSnapshot) -> some View {
        Label {
            Text(snapshot.repositoryRootURL.lastPathComponent)
                .fontWeight(.medium)
            Text(snapshot.branchName ?? "branch")
                .foregroundStyle(.secondary)
        } icon: {
            Image(nsImage: NSWorkspace.shared.icon(for: .folder))
                .resizable()
                .frame(width: 16, height: 16)
        }
        .lineLimit(1)
    }

    // MARK: - File Rows

    @ViewBuilder
    private func fileRows(_ files: [GitChangedFile], staged: Bool, snapshot: GitRepositoryStatusSnapshot) -> some View {
        let prefix = staged ? "staged" : "unstaged"
        ForEach(files.map { (id: "\(prefix):\($0.repositoryRelativePath)", file: $0) }, id: \.id) { entry in
            FileLabel(name: entry.file.fileURL.lastPathComponent, icon: entry.file.fileURL.fileIcon) {
                GitStatusBadge(kind: entry.file.kind, staged: staged)
            }
            .tag(entry.id)
            .contextMenu {
                GitFileContextMenu(files: [entry.file], staged: staged, snapshot: snapshot, onAction: handleAction)
            }
        }
    }

    // MARK: - Actions

    private func handleAction(_ action: GitAction) {
        switch action {
        case .stage(let files, let snapshot):
            Task { await model.stage(files: files, snapshot: snapshot); await model.refresh(directoryURL: directoryURL) }
        case .unstage(let files, let snapshot):
            Task { await model.unstage(files: files, snapshot: snapshot); await model.refresh(directoryURL: directoryURL) }
        case .stageAll(let snapshot):
            Task { await model.stageAll(snapshot: snapshot); await model.refresh(directoryURL: directoryURL) }
        case .unstageAll(let snapshot):
            Task { await model.unstageAll(snapshot: snapshot); await model.refresh(directoryURL: directoryURL) }
        case .discard(let files, let snapshot):
            discardTarget = .files(files, snapshot)
        case .discardAll(let snapshot):
            discardTarget = .all(snapshot)
        case .commit:
            commitMessage = ""
            showCommitSheet = true
        case .openFile(let url):
            editorPanel.openFile(url)
        }
    }

    // MARK: - Discard

    private enum DiscardTarget {
        case files([GitChangedFile], GitRepositoryStatusSnapshot)
        case all(GitRepositoryStatusSnapshot)
    }

    private var discardAlertBinding: Binding<Bool> {
        Binding(get: { discardTarget != nil }, set: { if !$0 { discardTarget = nil } })
    }

    private var discardAlertMessage: String {
        switch discardTarget {
        case .files(let files, _) where files.count == 1:
            "This will discard changes to \"\(files[0].repositoryRelativePath)\". This cannot be undone."
        case .files(let files, _):
            "This will discard changes to \(files.count) files. This cannot be undone."
        case .all:
            "This will discard all unstaged changes. This cannot be undone."
        case .none:
            ""
        }
    }

    private func performDiscard(_ target: DiscardTarget) async {
        switch target {
        case .files(let files, let snapshot): await model.discardChanges(files: files, snapshot: snapshot)
        case .all(let snapshot): await model.discardAllChanges(snapshot: snapshot)
        }
    }

    // MARK: - Helpers

    private func expandAllRepos() {
        for snapshot in model.snapshots {
            expandedRepos.insert(snapshot.repositoryRootURL)
        }
    }

    private func resolveFile(id: String) -> (GitChangedFile, Bool, GitRepositoryStatusSnapshot)? {
        let staged = id.hasPrefix("staged:")
        let path = String(id.drop(while: { $0 != ":" }).dropFirst())
        for snapshot in model.snapshots {
            let files = staged ? snapshot.stagedFiles : snapshot.unstagedFiles
            if let file = files.first(where: { $0.repositoryRelativePath == path }) {
                return (file, staged, snapshot)
            }
        }
        return nil
    }

    private func repoBinding(_ url: URL) -> Binding<Bool> {
        Binding(
            get: { expandedRepos.contains(url) },
            set: { if $0 { expandedRepos.insert(url) } else { expandedRepos.remove(url) } }
        )
    }
}
