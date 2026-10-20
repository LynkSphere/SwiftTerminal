import SwiftUI

struct GitBranchListSheet: View {
    let directoryURL: URL
    @Bindable var state: GitInspectorState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @State private var listing = GitBranchListing()
    @State private var isLoading = true
    @State private var worktreePendingDelete: GitWorktreeInfo?
    @State private var worktreePendingConversion: GitWorktreeInfo?

    private var snapshot: GitRepositoryStatusSnapshot? { state.currentSnapshot }

    private var localBranches: [GitBranchInfo] {
        listing.branches.filter { branch in
            !branch.isRemote && !linkedWorktrees.contains { $0.branch == branch.name }
        }
    }
    private var remoteBranches: [GitBranchInfo] { listing.branches.filter { $0.isRemote } }
    private var linkedWorktrees: [GitWorktreeInfo] { listing.worktrees.filter { !$0.isMain && !$0.isBare } }
    private var currentBranchName: String? { listing.branches.first(where: { $0.isCurrent })?.name }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if listing.branches.isEmpty && linkedWorktrees.isEmpty {
                    ContentUnavailableView(
                        "No Branches",
                        systemImage: "arrow.triangle.branch",
                        description: Text("This repository has no branches or linked worktrees.")
                    )
                } else {
                    List {
                        if !localBranches.isEmpty {
                            Section("Local") {
                                ForEach(localBranches) { branch in
                                    branchRow(branch)
                                        .contextMenu {
                                            compareMenu(for: branch)
                                            if listing.deletionUnavailableReason(for: branch) == nil {
                                                Divider()
                                                deleteButton(branch)
                                            }
                                        }
                                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            if listing.deletionUnavailableReason(for: branch) == nil {
                                                deleteButton(branch)
                                            }
                                        }
                                }
                            }
                        }
                        if !linkedWorktrees.isEmpty {
                            Section("Worktrees") {
                                ForEach(linkedWorktrees) { worktree in
                                    GitBranchRow(
                                        name: worktree.branch ?? "Detached · \(worktree.head?.prefix(7) ?? "")",
                                        subtitle: worktree.path.path(percentEncoded: false),
                                        icon: "folder",
                                        isCurrent: worktree.isCurrent,
                                        isMerged: listing.mergedWorktreePaths.contains(worktree.path)
                                    )
                                    .contextMenu {
                                        if let branch = listing.branches.first(where: { !$0.isRemote && $0.name == worktree.branch }) {
                                            compareMenu(for: branch)
                                            if !branch.isCurrent {
                                                Divider()
                                            }
                                        }
                                        if !worktree.isCurrent {
                                            if worktree.branch != nil {
                                                convertWorktreeButton(worktree)
                                            }
                                            deleteWorktreeButton(worktree)
                                        }
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        if !worktree.isCurrent {
                                            deleteWorktreeButton(worktree)
                                        }
                                    }
                                }
                            }
                        }
                        if !remoteBranches.isEmpty {
                            Section("Remote") {
                                ForEach(remoteBranches) { branch in
                                    branchRow(branch)
                                        .contextMenu { compareMenu(for: branch) }
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle("Branches")
            .navigationSubtitle(listing.mergeTarget.map { "Merged into \($0)" } ?? "Merge target unavailable")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(width: 420, height: 440)
        .task { await load() }
        .alert("Delete Unmerged Branch?", isPresented: deleteAlertBinding) {
            Button("Delete", role: .confirm) {
                guard let branch = state.branchPendingDelete else { return }
                state.branchPendingDelete = nil
                Task {
                    guard let snap = state.currentSnapshot else { return }
                    guard await state.model.deleteBranch(branch.name, force: true, snapshot: snap) else { return }
                    await load()
                    await state.refresh(directoryURL: directoryURL)
                }
            }
            Button("Cancel", role: .cancel) { state.branchPendingDelete = nil }
        } message: {
            Text("\"\(state.branchPendingDelete?.name ?? "")\" is not fully merged into the current branch. Deleting it may discard commits permanently.")
        }
        .alert("Delete Worktree?", isPresented: worktreeDeleteAlertBinding, presenting: worktreePendingDelete) { worktree in
            Button("Delete", role: .destructive) {
                worktreePendingDelete = nil
                deleteWorktree(worktree)
            }
            Button("Cancel", role: .cancel) { worktreePendingDelete = nil }
        } message: { worktree in
            if let branch = worktree.branch {
                Text("This deletes the folder at \(worktree.path.path) and the local branch \"\(branch)\". Unmerged commits may be lost. Worktrees with uncommitted changes cannot be deleted.")
            } else {
                Text("This removes the folder at \(worktree.path.path). Detached commits not saved on a branch may become unreachable. Worktrees with uncommitted changes cannot be deleted.")
            }
        }
        .alert("Convert to Branch?", isPresented: worktreeConversionAlertBinding, presenting: worktreePendingConversion) { worktree in
            Button("Convert") {
                worktreePendingConversion = nil
                convertWorktree(worktree)
            }
            Button("Cancel", role: .cancel) { worktreePendingConversion = nil }
        } message: { worktree in
            Text("This switches the main checkout to \"\(worktree.branch ?? "")\" and removes the worktree folder at \(worktree.path.path). The branch and its commits are kept. Both checkouts must have no uncommitted changes.")
        }
        .alert("Git Operation Failed", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.model.errorMessage ?? "")
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { state.branchPendingDelete != nil },
            set: { if !$0 { state.branchPendingDelete = nil } }
        )
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { state.model.errorMessage != nil },
            set: { if !$0 { state.model.errorMessage = nil } }
        )
    }

    private var worktreeDeleteAlertBinding: Binding<Bool> {
        Binding(
            get: { worktreePendingDelete != nil },
            set: { if !$0 { worktreePendingDelete = nil } }
        )
    }

    private var worktreeConversionAlertBinding: Binding<Bool> {
        Binding(
            get: { worktreePendingConversion != nil },
            set: { if !$0 { worktreePendingConversion = nil } }
        )
    }

    @ViewBuilder
    private func compareMenu(for branch: GitBranchInfo) -> some View {
        if !branch.isCurrent, let head = currentBranchName {
            if branch.upstream != nil {
                Button {
                    syncWithUpstream(for: branch)
                } label: {
                    Label("Sync with Upstream", systemImage: "arrow.triangle.2.circlepath")
                }
                Divider()
            }
            Button {
                openCompare(base: branch.name, head: head)
            } label: {
                Label("Compare Commits with \(head)…", systemImage: "arrow.left.arrow.right")
            }
        }
    }

    private func syncWithUpstream(for branch: GitBranchInfo) {
        guard let snapshot else { return }
        Task {
            await state.model.syncBranchWithUpstream(branch, snapshot: snapshot)
            await load()
            await state.refresh(directoryURL: directoryURL)
        }
    }

    private func openCompare(base: String, head: String) {
        guard let snapshot else { return }
        openWindow(value: GitCommitDiffSheetItem(
            range: GitBranchRange(base: base, head: head),
            message: "Committed changes only",
            repositoryRootURL: snapshot.repositoryRootURL
        ))
        dismiss()
    }

    private func branchRow(_ branch: GitBranchInfo) -> some View {
        GitBranchRow(
            name: branch.name,
            icon: branch.isRemote ? "cloud" : "arrow.triangle.branch",
            isCurrent: branch.isCurrent,
            isMerged: branch.isMerged
        )
    }

    private func canDelete(_ branch: GitBranchInfo) -> Bool {
        listing.deletionUnavailableReason(for: branch) == nil && !state.model.isBusy
    }

    private func handleDelete(_ branch: GitBranchInfo) {
        guard let snapshot, canDelete(branch) else { return }
        if branch.isMergedIntoCurrentBranch {
            Task {
                guard await state.model.deleteBranch(branch.name, force: false, snapshot: snapshot) else { return }
                await load()
                await state.refresh(directoryURL: directoryURL)
            }
        } else {
            state.branchPendingDelete = branch
        }
    }

    private func deleteButton(_ branch: GitBranchInfo) -> some View {
        Button(role: .destructive) {
            handleDelete(branch)
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .disabled(!canDelete(branch))
        .help(listing.deletionUnavailableReason(for: branch) ?? "Delete this local branch")
    }

    private func deleteWorktreeButton(_ worktree: GitWorktreeInfo) -> some View {
        Button("Delete", systemImage: "trash", role: .destructive) {
            worktreePendingDelete = worktree
        }
        .disabled(worktree.deletionUnavailableReason != nil || state.model.isBusy)
        .help(worktree.deletionUnavailableReason ?? "Delete the worktree folder and its local branch")
    }

    private func convertWorktreeButton(_ worktree: GitWorktreeInfo) -> some View {
        Button("Convert to Branch", systemImage: "arrow.triangle.branch") {
            worktreePendingConversion = worktree
        }
        .disabled(worktree.deletionUnavailableReason != nil || state.model.isBusy)
        .help(worktree.deletionUnavailableReason ?? "Keep this branch in the main checkout and remove its worktree folder")
    }

    private func deleteWorktree(_ worktree: GitWorktreeInfo) {
        guard let snapshot, worktree.deletionUnavailableReason == nil, !state.model.isBusy else { return }
        Task {
            let succeeded = await state.model.deleteWorktree(worktree, snapshot: snapshot)
            let error = state.model.errorMessage
            await state.refresh(directoryURL: directoryURL)
            await load()
            if !succeeded { state.model.errorMessage = error }
        }
    }

    private func convertWorktree(_ worktree: GitWorktreeInfo) {
        guard let snapshot, worktree.deletionUnavailableReason == nil, !state.model.isBusy else { return }
        Task {
            let succeeded = await state.model.convertWorktreeToBranch(worktree, snapshot: snapshot)
            let error = state.model.errorMessage
            if succeeded {
                state.worktreeOverrides.removeValue(forKey: snapshot.mainRepositoryURL)
                state.selectedRepoURL = snapshot.mainRepositoryURL
            }
            let viewedRoot = snapshot.repositoryRootURL
            let directory = directoryURL.standardizedFileURL.resolvingSymlinksInPath()
            let refreshURL = snapshot.isLinkedWorktree && (viewedRoot == directory || viewedRoot.isAncestor(of: directory))
                ? snapshot.mainRepositoryURL : directoryURL
            await state.refresh(directoryURL: refreshURL)
            await load()
            if !succeeded { state.model.errorMessage = error }
        }
    }

    private func load() async {
        guard let snapshot else {
            isLoading = false
            return
        }
        isLoading = listing.branches.isEmpty
        listing = await state.model.branches(snapshot: snapshot)
        isLoading = false
    }
}
