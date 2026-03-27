import SwiftUI
import UniformTypeIdentifiers

struct GitInspectorView: View {
    let directoryURL: URL

    @Environment(EditorPanel.self) private var editorPanel
    @State private var model = GitInspectorModel()
    @State private var selectedRepoURL: URL?
    @State private var selectedFileID: String?
    @State private var commitMessage = ""
    @State private var discardTarget: DiscardTarget?
    @State private var pendingBranchSwitch: String?
    @State private var showNewBranchSheet = false
    @State private var newBranchName = ""

    private var selectedSnapshot: GitRepositoryStatusSnapshot? {
        model.snapshots.first { $0.repositoryRootURL == selectedRepoURL }
            ?? model.snapshots.first
    }

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
                if selectedRepoURL == nil {
                    selectedRepoURL = model.snapshots.first?.repositoryRootURL
                }
            }
            .task(id: directoryURL, priority: .low) {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { break }
                    await model.refresh(directoryURL: directoryURL)
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
            .alert("Stash Changes?", isPresented: stashAlertBinding) {
                Button("Stash & Switch", role: .destructive) {
                    guard let branch = pendingBranchSwitch, let snapshot = selectedSnapshot else { return }
                    Task {
                        await model.stashAndSwitch(to: branch, snapshot: snapshot)
                        await model.refresh(directoryURL: directoryURL)
                    }
                }
                Button("Cancel", role: .cancel) { pendingBranchSwitch = nil }
            } message: {
                Text("You have uncommitted changes. Stash all changes (including staged and untracked) before switching branches?")
            }
            .sheet(isPresented: $showNewBranchSheet) {
                newBranchSheet
            }
            .onChange(of: selectedFileID) { _, newID in
                guard let id = newID else { return }
                guard let (file, stage, snapshot) = resolveFile(id: id) else { return }
                editorPanel.openDiff(GitDiffReference(
                    repositoryRootURL: snapshot.repositoryRootURL,
                    fileURL: file.fileURL,
                    repositoryRelativePath: file.repositoryRelativePath,
                    stage: stage,
                    kind: file.kind
                ))
            }
    }

    // MARK: - List

    @State private var stagedExpanded = true
    @State private var unstagedExpanded = true

    private var changesList: some View {
        List(selection: $selectedFileID) {
            if let snapshot = selectedSnapshot {
                if !snapshot.stagedFiles.isEmpty {
                    DisclosureGroup(isExpanded: $stagedExpanded) {
                        fileRows(snapshot.stagedFiles, staged: true, snapshot: snapshot)
                    } label: {
                        Label("Staged Changes", systemImage: "checkmark.circle")
                            .font(.subheadline)
                            .lineLimit(1)
                            .contextMenu { GitRepoContextMenu(snapshot: snapshot, onAction: handleAction) }
                    }
                    .listRowSeparator(.hidden)
                }

                if !snapshot.unstagedFiles.isEmpty {
                    DisclosureGroup(isExpanded: $unstagedExpanded) {
                        fileRows(snapshot.unstagedFiles, staged: false, snapshot: snapshot)
                    } label: {
                        Label("Changes", systemImage: "circle.dashed")
                            .font(.subheadline)
                            .lineLimit(1)
                            .contextMenu { GitRepoContextMenu(snapshot: snapshot, onAction: handleAction) }
                    }
                    .listRowSeparator(.hidden)
                }

                ForEach(snapshot.unpushedCommits) { commit in
                    DisclosureGroup {
                        commitFileRows(commit.files, commit: commit, snapshot: snapshot)
                    } label: {
                        Label(commit.message, systemImage: "circle.fill")
                            .font(.subheadline)
                            .lineLimit(1)
                            .contextMenu {
                                GitCommitContextMenu(commit: commit, snapshot: snapshot, onAction: handleAction)
                            }
                    }
                    .listRowSeparator(.hidden)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .safeAreaBar(edge: .top) {
            VStack(spacing: 8) {
                branchRow
                
                commitArea
                    .padding(.horizontal, 5)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .padding(.top, 8)
        }
        .safeAreaBar(edge: .bottom) {
            if model.snapshots.count > 1 {
                repoPicker
                    .padding()
            }
        }
    }

    // MARK: - Repo Picker

    private var repoPicker: some View {
        Picker(selection: $selectedRepoURL) {
            ForEach(model.snapshots, id: \.repositoryRootURL) { snapshot in
                Label {
                    Text(snapshot.repositoryRootURL.lastPathComponent)
                } icon: {
                    Image(systemName: "arrow.right.arrow.left")
                }
                .lineLimit(1)
                .tag(Optional(snapshot.repositoryRootURL))
            }
        } label: {
//            EmptyView()
        }
        .pickerStyle(.menu)
        .controlSize(.large)
    }

    // MARK: - Branch Row

    private var branchRow: some View {
        HStack(spacing: 4) {
            Menu {
                if let snapshot = selectedSnapshot {
                    ForEach(snapshot.localBranches, id: \.self) { branch in
                        Button {
                            switchToBranch(branch)
                        } label: {
                            HStack {
                                Text(branch)
                                if branch == snapshot.branchName {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .disabled(branch == snapshot.branchName)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.caption)
                    Text(selectedSnapshot?.branchName ?? "No Branch")
                        .font(.subheadline)
                        .lineLimit(1)
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            
            Spacer()

            Menu {
                Button {
                    newBranchName = ""
                    showNewBranchSheet = true
                } label: {
                    Label("New Branch...", systemImage: "plus")
                }

                Divider()

                Button {
                    guard let snapshot = selectedSnapshot else { return }
                    Task {
                        await model.fetch(snapshot: snapshot)
                        await model.refresh(directoryURL: directoryURL)
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private func switchToBranch(_ branch: String) {
        guard let snapshot = selectedSnapshot else { return }
        if snapshot.isDirty {
            pendingBranchSwitch = branch
        } else {
            Task {
                await model.switchBranch(to: branch, snapshot: snapshot)
                await model.refresh(directoryURL: directoryURL)
            }
        }
    }

    private var stashAlertBinding: Binding<Bool> {
        Binding(get: { pendingBranchSwitch != nil }, set: { if !$0 { pendingBranchSwitch = nil } })
    }

    private var newBranchSheet: some View {
        VStack(spacing: 12) {
            Text("New Branch")
                .font(.headline)

            Text("Create a new branch from \"\(selectedSnapshot?.branchName ?? "HEAD")\"")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("Branch name", text: $newBranchName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    showNewBranchSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    guard let snapshot = selectedSnapshot else { return }
                    let name = newBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    showNewBranchSheet = false
                    Task {
                        await model.createBranch(named: name, snapshot: snapshot)
                        await model.refresh(directoryURL: directoryURL)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
    }

    // MARK: - Commit Area

    private enum SourceControlAction {
        case commit
        case push
        case pull

        var label: String {
            switch self {
                case .commit: "Commit"
                case .push: "Push"
                case .pull: "Pull"
            }
        }

        var systemImage: String {
            switch self {
                case .commit: "checkmark.circle"
                case .push: "arrow.up"
                case .pull: "arrow.down"
            }
        }
    }

    private var currentAction: SourceControlAction {
        guard let snapshot = selectedSnapshot else { return .commit }
        if !snapshot.stagedFiles.isEmpty { return .commit }
        if !snapshot.unpushedCommits.isEmpty { return .push }
        if snapshot.remoteAheadCount > 0 { return .pull }
        return .commit
    }

    private var commitArea: some View {
        VStack(spacing: 6) {
            TextField("Commit message", text: $commitMessage, axis: .vertical)
                .lineLimit(1...4)

            Button {
                performSourceControlAction()
            } label: {
                Text(currentAction.label)
            }
            .buttonSizing(.flexible)
            .buttonStyle(.borderedProminent)
            .disabled(currentAction == .commit && commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func performSourceControlAction() {
        guard let snapshot = selectedSnapshot else { return }
        switch currentAction {
        case .commit:
            let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty, !snapshot.stagedFiles.isEmpty else { return }
            Task {
                await model.commit(message: message, snapshot: snapshot)
                commitMessage = ""
                await model.refresh(directoryURL: directoryURL)
            }
        case .push:
            Task {
                await model.push(snapshot: snapshot)
                await model.refresh(directoryURL: directoryURL)
            }
        case .pull:
            Task {
                await model.pull(snapshot: snapshot)
                await model.refresh(directoryURL: directoryURL)
            }
        }
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
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private func commitFileRows(_ files: [GitChangedFile], commit: GitUnpushedCommit, snapshot: GitRepositoryStatusSnapshot) -> some View {
        ForEach(files.map { (id: "commit:\(commit.hash):\($0.repositoryRelativePath)", file: $0) }, id: \.id) { entry in
            FileLabel(name: entry.file.fileURL.lastPathComponent, icon: entry.file.fileURL.fileIcon) {
                GitStatusBadge(kind: entry.file.kind, staged: true)
            }
            .tag(entry.id)
        }
        .listRowSeparator(.hidden)
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
            performSourceControlAction()
        case .openFile(let url):
            editorPanel.openFile(url)
        case .push(let snapshot):
            Task { await model.push(snapshot: snapshot); await model.refresh(directoryURL: directoryURL) }
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

    private func resolveFile(id: String) -> (GitChangedFile, GitDiffStage, GitRepositoryStatusSnapshot)? {
        guard let snapshot = selectedSnapshot else { return nil }

        if id.hasPrefix("commit:") {
            let remainder = id.dropFirst(7) // drop "commit:"
            guard let separatorIndex = remainder.firstIndex(of: ":") else { return nil }
            let hash = String(remainder[remainder.startIndex..<separatorIndex])
            let path = String(remainder[remainder.index(after: separatorIndex)...])
            if let commit = snapshot.unpushedCommits.first(where: { $0.hash == hash }),
               let file = commit.files.first(where: { $0.repositoryRelativePath == path }) {
                return (file, .commit(hash: hash), snapshot)
            }
            return nil
        }

        let staged = id.hasPrefix("staged:")
        let path = String(id.drop(while: { $0 != ":" }).dropFirst())
        let files = staged ? snapshot.stagedFiles : snapshot.unstagedFiles
        if let file = files.first(where: { $0.repositoryRelativePath == path }) {
            return (file, staged ? .staged : .unstaged, snapshot)
        }
        return nil
    }
}
