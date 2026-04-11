import SwiftUI

struct GitInspectorChangesList: View {
    let directoryURL: URL
    @Bindable var state: GitInspectorState
    var onShowInFileTree: ((URL) -> Void)?

    @Environment(EditorPanel.self) private var editorPanel

    private var snapshot: GitRepositoryStatusSnapshot? { state.currentSnapshot }

    var body: some View {
        List(selection: $state.selectedFileID) {
            if let snapshot {
                if !snapshot.stagedFiles.isEmpty {
                    Section(isExpanded: $state.stagedExpanded) {
                        fileRows(snapshot.stagedFiles, staged: true, snapshot: snapshot)
                    } header: {
                        sectionHeader(
                            title: "Staged Changes",
                            systemImage: "checkmark.circle",
                            isExpanded: $state.stagedExpanded
                        )
                        .contextMenu { GitRepoContextMenu(snapshot: snapshot, onAction: handleAction) }
                    }
                }

                if !snapshot.unstagedFiles.isEmpty {
                    Section(isExpanded: $state.unstagedExpanded) {
                        fileRows(snapshot.unstagedFiles, staged: false, snapshot: snapshot)
                    } header: {
                        sectionHeader(
                            title: "Changes",
                            systemImage: "circle.dashed",
                            isExpanded: $state.unstagedExpanded
                        )
                        .contextMenu { GitRepoContextMenu(snapshot: snapshot, onAction: handleAction) }
                    }
                }

                ForEach(snapshot.unpushedCommits) { commit in
                    let binding = commitExpandedBinding(for: commit.hash)
                    Section(isExpanded: binding) {
                        commitFileRows(commit.files, commit: commit)
                    } header: {
                        sectionHeader(
                            title: commit.message,
                            systemImage: "circle.fill",
                            isExpanded: binding
                        )
                        .contextMenu {
                            GitCommitContextMenu(commit: commit, snapshot: snapshot, onAction: handleAction)
                        }
                    }
                }
            }
        }
        .contextMenu(forSelectionType: String.self) { items in
            if let id = items.first, let (file, stage, snap) = resolveFile(id: id) {
                let staged = stage == .staged
                if !id.hasPrefix("commit:") {
                    GitFileContextMenu(files: [file], staged: staged, snapshot: snap, onAction: handleAction)
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
        .onChange(of: state.selectedFileID) { _, newID in
            guard let id = newID,
                  let (file, stage, snap) = resolveFile(id: id) else { return }
            editorPanel.openDiff(file.fileURL, in: snap.repositoryRootURL, stage: stage, kind: file.kind)
        }
    }

    // MARK: - Section Header

    @ViewBuilder
    private func sectionHeader(title: String, systemImage: String, isExpanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Label {
                    Text(title)
                } icon: {
                    Image(systemName: systemImage)
                    .foregroundStyle(.accent)
                }
                .font(.subheadline)
                .lineLimit(1)
                
                Spacer(minLength: 4)
                
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Rows

    private struct GitFileRow: Identifiable, Hashable {
        let id: String
        let file: GitChangedFile
    }

    @ViewBuilder
    private func fileRows(_ files: [GitChangedFile], staged: Bool, snapshot: GitRepositoryStatusSnapshot) -> some View {
        let prefix = staged ? "staged" : "unstaged"
        let rows = files.map { GitFileRow(id: "\(prefix):\($0.repositoryRelativePath)", file: $0) }
        ForEach(rows) { row in
            FileLabel(name: row.file.fileURL.lastPathComponent, icon: row.file.fileURL.fileIcon) {
                GitStatusBadge(kind: row.file.kind, staged: staged)
                    .overlay {
                        Menu {
                            GitFileContextMenu(files: [row.file], staged: staged, snapshot: snapshot, onAction: handleAction)
                        } label: {
                            Color.clear.contentShape(Rectangle())
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                    }
            }
            .tag(row.id)
        }
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private func commitFileRows(_ files: [GitChangedFile], commit: GitUnpushedCommit) -> some View {
        let rows = files.map { GitFileRow(id: "commit:\(commit.hash):\($0.repositoryRelativePath)", file: $0) }
        ForEach(rows) { row in
            FileLabel(name: row.file.fileURL.lastPathComponent, icon: row.file.fileURL.fileIcon) {
                GitStatusBadge(kind: row.file.kind, staged: true)
            }
            .tag(row.id)
        }
        .listRowSeparator(.hidden)
    }

    // MARK: - Bindings & Helpers

    private func commitExpandedBinding(for hash: String) -> Binding<Bool> {
        Binding(
            get: { state.expandedCommitHashes.contains(hash) },
            set: { isExpanded in
                if isExpanded {
                    state.expandedCommitHashes.insert(hash)
                } else {
                    state.expandedCommitHashes.remove(hash)
                }
            }
        )
    }

    private func resolveFile(id: String) -> (GitChangedFile, GitDiffStage, GitRepositoryStatusSnapshot)? {
        guard let snapshot else { return nil }

        if id.hasPrefix("commit:") {
            let remainder = id.dropFirst(7)
            guard let separator = remainder.firstIndex(of: ":") else { return nil }
            let hash = String(remainder[remainder.startIndex..<separator])
            let path = String(remainder[remainder.index(after: separator)...])
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

    // MARK: - Action Dispatch

    private func handleAction(_ action: GitAction) {
        switch action {
        case .showInFileTree(let url):
            onShowInFileTree?(url)
        case .commit:
            // Commit is handled by the commit area; ignore from list-side menus.
            break
        default:
            state.perform(action, directoryURL: directoryURL)
        }
    }
}
