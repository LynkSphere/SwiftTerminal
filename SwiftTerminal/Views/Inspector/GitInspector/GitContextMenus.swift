import SwiftUI

// MARK: - Action Enum

enum GitAction {
    case stage([GitChangedFile], GitRepositoryStatusSnapshot)
    case unstage([GitChangedFile], GitRepositoryStatusSnapshot)
    case stageAll(GitRepositoryStatusSnapshot)
    case unstageAll(GitRepositoryStatusSnapshot)
    case discard([GitChangedFile], GitRepositoryStatusSnapshot)
    case discardAll(GitRepositoryStatusSnapshot)
    case commit
    case openFile(URL)
}

// MARK: - Context Menus

struct GitRepoContextMenu: View {
    let snapshot: GitRepositoryStatusSnapshot
    let onAction: (GitAction) -> Void

    var body: some View {
        Button { onAction(.stageAll(snapshot)) } label: {
            Label("Stage All Changes", systemImage: "tray.and.arrow.down")
        }
        .disabled(snapshot.unstagedFiles.isEmpty)

        Button { onAction(.unstageAll(snapshot)) } label: {
            Label("Unstage All Changes", systemImage: "tray.and.arrow.up")
        }
        .disabled(snapshot.stagedFiles.isEmpty)

        Button(role: .destructive) { onAction(.discardAll(snapshot)) } label: {
            Label("Discard All Changes", systemImage: "arrow.uturn.backward")
        }
        .disabled(snapshot.unstagedFiles.isEmpty)

        Divider()

        Button { onAction(.commit) } label: {
            Label("Commit...", systemImage: "checkmark.circle")
        }
        .disabled(snapshot.stagedFiles.isEmpty)
    }
}

struct GitFileContextMenu: View {
    let files: [GitChangedFile]
    let staged: Bool
    let snapshot: GitRepositoryStatusSnapshot
    let onAction: (GitAction) -> Void

    var body: some View {
        if let file = files.first, files.count == 1 {
            Button { onAction(.openFile(file.fileURL)) } label: {
                Label("Open File", systemImage: "doc")
            }

            Divider()
        }

        Button { onAction(.stage(files, snapshot)) } label: {
            Label("Stage Changes", systemImage: "tray.and.arrow.down")
        }
        .disabled(staged)

        Button { onAction(.unstage(files, snapshot)) } label: {
            Label("Unstage Changes", systemImage: "tray.and.arrow.up")
        }
        .disabled(!staged)

        Divider()

        Button(role: .destructive) { onAction(.discard(files, snapshot)) } label: {
            Label("Discard Changes", systemImage: "arrow.uturn.backward")
        }
        .disabled(staged)

        Divider()

        Button { onAction(.commit) } label: {
            Label("Commit...", systemImage: "checkmark.circle")
        }
        .disabled(snapshot.stagedFiles.isEmpty)
    }
}
