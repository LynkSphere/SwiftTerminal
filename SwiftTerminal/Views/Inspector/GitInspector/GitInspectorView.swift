import SwiftUI

struct GitInspectorView: View {
    let directoryURL: URL
    @Bindable var state: GitInspectorState
    var onShowInFileTree: ((URL) -> Void)?

    @Environment(EditorPanel.self) private var editorPanel

    private var selectedSnapshot: GitRepositoryStatusSnapshot? {
        state.model.snapshots.first { $0.repositoryRootURL == state.selectedRepoURL }
            ?? state.model.snapshots.first
    }

    var body: some View {
        changesList
            .overlay {
                if state.model.isLoading && state.model.snapshots.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .overlay(alignment: .bottom) {
                if let error = state.model.errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text(error)
                            .lineLimit(3)
                        Spacer()
                        Button {
                            state.model.errorMessage = nil
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.caption)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(5))
                        if state.model.errorMessage == error {
                            state.model.errorMessage = nil
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: state.model.errorMessage)
            .task(id: directoryURL) {
                await state.model.refresh(directoryURL: directoryURL)
                if state.selectedRepoURL == nil {
                    state.selectedRepoURL = state.model.snapshots.first?.repositoryRootURL
                }
            }
            .task(id: selectedSnapshot?.branchName) {
                guard let snapshot = selectedSnapshot else { return }
                await state.model.fetch(snapshot: snapshot)
                await state.model.refresh(directoryURL: directoryURL)
            }
            .gitPolling(id: directoryURL) {
                await state.model.refresh(directoryURL: directoryURL)
            }
            .alert("Discard Changes?", isPresented: discardAlertBinding) {
                Button("Discard", role: .destructive) {
                    guard let target = state.discardTarget else { return }
                    Task {
                        await performDiscard(target)
                        await state.model.refresh(directoryURL: directoryURL)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(discardAlertMessage)
            }
            .alert("Stash Changes?", isPresented: stashAlertBinding) {
                Button("Stash & Switch", role: .destructive) {
                    guard let branch = state.pendingBranchSwitch, let snapshot = selectedSnapshot else { return }
                    Task {
                        await state.model.stashAndSwitch(to: branch, snapshot: snapshot)
                        await state.model.refresh(directoryURL: directoryURL)
                    }
                }
                Button("Cancel", role: .cancel) { state.pendingBranchSwitch = nil }
            } message: {
                Text("You have uncommitted changes. Stash all changes (including staged and untracked) before switching branches?")
            }
            .sheet(isPresented: $state.showNewBranchSheet) {
                newBranchSheet
            }
            .alert("Stash All Changes", isPresented: $state.showStashAlert) {
                TextField("Stash name", text: $state.stashMessage)
                Button("Stash") {
                    guard let snapshot = selectedSnapshot else { return }
                    let message = state.stashMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !message.isEmpty else { return }
                    Task {
                        await state.model.stashAll(message: message, snapshot: snapshot)
                        state.stashMessage = ""
                        await state.model.refresh(directoryURL: directoryURL)
                    }
                }
                Button("Cancel", role: .cancel) { state.stashMessage = "" }
            } message: {
                Text("Stash all staged, unstaged, and untracked changes.")
            }
            .onChange(of: state.selectedFileID) { _, newID in
                guard let id = newID else { return }
                guard let (file, stage, snapshot) = resolveFile(id: id) else { return }
                editorPanel.openDiff(file.fileURL, in: snapshot.repositoryRootURL, stage: stage, kind: file.kind)
            }
    }

    // MARK: - List

    private var changesList: some View {
        List(selection: $state.selectedFileID) {
            if let snapshot = selectedSnapshot {
                if !snapshot.stagedFiles.isEmpty {
                    DisclosureGroup(isExpanded: $state.stagedExpanded) {
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
                    DisclosureGroup(isExpanded: $state.unstagedExpanded) {
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
        .contextMenu(forSelectionType: String.self) { items in
            if let id = items.first, let (file, stage, snapshot) = resolveFile(id: id) {
                let staged = stage == .staged
                if !id.hasPrefix("commit:") {
                    GitFileContextMenu(files: [file], staged: staged, snapshot: snapshot, onAction: handleAction)
                } else if file.kind != .deleted {
                    Button { onShowInFileTree?(file.fileURL) } label: {
                        Label("Show in File Tree", systemImage: "sidebar.trailing")
                    }
                }
            }
        } primaryAction: { items in
            for id in items {
                if let (file, _, _) = resolveFile(id: id) {
                    editorPanel.openFile(file.fileURL)
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
            .padding(.top, 7)
        }
        .safeAreaBar(edge: .bottom) {
            if state.model.snapshots.count > 1 {
                repoPicker
                    .padding()
            }
        }
    }

    // MARK: - Repo Picker

    private var repoPicker: some View {
        Picker(selection: $state.selectedRepoURL) {
            ForEach(state.model.snapshots, id: \.repositoryRootURL) { snapshot in
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
        .buttonSizing(.flexible)
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
                Label {
                    Text(selectedSnapshot?.branchName ?? "No Branch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "arrow.triangle.branch")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
//            .menuIndicator(.hidden)
            
            Spacer()

            Menu {
                Button {
                    state.newBranchName = ""
                    state.showNewBranchSheet = true
                } label: {
                    Label("New Branch...", systemImage: "plus")
                }

                Divider()

                Button {
                    state.stashMessage = ""
                    state.showStashAlert = true
                } label: {
                    Label("Stash All...", systemImage: "tray.and.arrow.down")
                }
                .disabled(selectedSnapshot?.isDirty != true)

                Button {
                    guard let snapshot = selectedSnapshot else { return }
                    Task {
                        await state.model.applyLatestStash(snapshot: snapshot)
                        await state.model.refresh(directoryURL: directoryURL)
                    }
                } label: {
                    Label("Apply Stash", systemImage: "tray.and.arrow.up")
                }

                Divider()

                Button {
                    guard let snapshot = selectedSnapshot else { return }
                    Task {
                        await state.model.fetch(snapshot: snapshot)
                        await state.model.refresh(directoryURL: directoryURL)
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
            state.pendingBranchSwitch = branch
        } else {
            Task {
                await state.model.switchBranch(to: branch, snapshot: snapshot)
                await state.model.refresh(directoryURL: directoryURL)
            }
        }
    }

    private var stashAlertBinding: Binding<Bool> {
        Binding(get: { state.pendingBranchSwitch != nil }, set: { if !$0 { state.pendingBranchSwitch = nil } })
    }

    private var newBranchSheet: some View {
        VStack(spacing: 12) {
            Text("New Branch")
                .font(.headline)

            Text("Create a new branch from \"\(selectedSnapshot?.branchName ?? "HEAD")\"")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("Branch name", text: $state.newBranchName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    state.showNewBranchSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    guard let snapshot = selectedSnapshot else { return }
                    let name = state.newBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    state.showNewBranchSheet = false
                    Task {
                        await state.model.createBranch(named: name, snapshot: snapshot)
                        await state.model.refresh(directoryURL: directoryURL)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(state.newBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
            TextField("Commit message", text: $state.commitMessage, axis: .vertical)
                .lineLimit(1...4)

            Button {
                performSourceControlAction()
            } label: {
                Text(currentAction.label)
            }
            .buttonSizing(.flexible)
            .buttonStyle(.borderedProminent)
            .disabled(currentAction == .commit && state.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func performSourceControlAction() {
        guard let snapshot = selectedSnapshot else { return }
        switch currentAction {
        case .commit:
            let message = state.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty, !snapshot.stagedFiles.isEmpty else { return }
            Task {
                await state.model.commit(message: message, snapshot: snapshot)
                state.commitMessage = ""
                await state.model.refresh(directoryURL: directoryURL)
            }
        case .push:
            Task {
                await state.model.push(snapshot: snapshot)
                await state.model.refresh(directoryURL: directoryURL)
            }
        case .pull:
            Task {
                await state.model.pull(snapshot: snapshot)
                await state.model.refresh(directoryURL: directoryURL)
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
                    .overlay {
                        Menu {
                            GitFileContextMenu(files: [entry.file], staged: staged, snapshot: snapshot, onAction: handleAction)
                        } label: {
                            Color.clear
                                .contentShape(Rectangle())
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                    }
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
            Task { await state.model.stage(files: files, snapshot: snapshot); await state.model.refresh(directoryURL: directoryURL) }
        case .unstage(let files, let snapshot):
            Task { await state.model.unstage(files: files, snapshot: snapshot); await state.model.refresh(directoryURL: directoryURL) }
        case .stageAll(let snapshot):
            Task { await state.model.stageAll(snapshot: snapshot); await state.model.refresh(directoryURL: directoryURL) }
        case .unstageAll(let snapshot):
            Task { await state.model.unstageAll(snapshot: snapshot); await state.model.refresh(directoryURL: directoryURL) }
        case .discard(let files, let snapshot):
            state.discardTarget = .files(files, snapshot)
        case .discardAll(let snapshot):
            state.discardTarget = .all(snapshot)
        case .commit:
            performSourceControlAction()
        case .showInFileTree(let url):
            onShowInFileTree?(url)
        case .push(let snapshot):
            Task { await state.model.push(snapshot: snapshot); await state.model.refresh(directoryURL: directoryURL) }
        }
    }

    // MARK: - Discard

    private var discardAlertBinding: Binding<Bool> {
        Binding(get: { state.discardTarget != nil }, set: { if !$0 { state.discardTarget = nil } })
    }

    private var discardAlertMessage: String {
        switch state.discardTarget {
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

    private func performDiscard(_ target: GitInspectorDiscardTarget) async {
        switch target {
        case .files(let files, let snapshot): await state.model.discardChanges(files: files, snapshot: snapshot)
        case .all(let snapshot): await state.model.discardAllChanges(snapshot: snapshot)
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
