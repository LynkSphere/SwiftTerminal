import SwiftUI

struct GitBranchListSheet: View {
    let directoryURL: URL
    @Bindable var state: GitInspectorState
    @Environment(\.dismiss) private var dismiss
    @State private var branches: [GitBranchInfo] = []
    @State private var isLoading = true

    private var snapshot: GitRepositoryStatusSnapshot? { state.currentSnapshot }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if branches.isEmpty {
                    ContentUnavailableView(
                        "No Branches",
                        systemImage: "arrow.triangle.branch",
                        description: Text("This repository has no local branches.")
                    )
                } else {
                    List {
                        ForEach(branches) { branch in
                            branchRow(branch)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if !branch.isCurrent {
                                        Button(role: .destructive) {
                                            handleDelete(branch)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle("Branches")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(width: 420, height: 440)
        .task { await load() }
        .alert("Delete Unmerged Branch?", isPresented: deleteAlertBinding) {
            Button("Delete", role: .destructive) {
                guard let branch = state.branchPendingDelete else { return }
                state.branchPendingDelete = nil
                Task {
                    guard let snap = state.currentSnapshot else { return }
                    _ = await state.model.deleteBranch(branch.name, force: true, snapshot: snap)
                    await load()
                    await state.refresh(directoryURL: directoryURL)
                }
            }
            Button("Cancel", role: .cancel) { state.branchPendingDelete = nil }
        } message: {
            Text("\"\(state.branchPendingDelete?.name ?? "")\" is not fully merged into the current branch. Deleting it may discard commits permanently.")
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { state.branchPendingDelete != nil },
            set: { if !$0 { state.branchPendingDelete = nil } }
        )
    }

    @ViewBuilder
    private func branchRow(_ branch: GitBranchInfo) -> some View {
        HStack(spacing: 8) {
            Image(systemName: branch.isCurrent ? "checkmark.circle.fill" : "arrow.triangle.branch")
                .foregroundStyle(branch.isCurrent ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(branch.name)
                    .font(.body)
                    .lineLimit(1)
                if let upstream = branch.upstream {
                    Text(upstream)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if branch.isMerged && !branch.isCurrent {
                Text("Merged")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.background.secondary, in: Capsule())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func handleDelete(_ branch: GitBranchInfo) {
        guard let snapshot, !branch.isCurrent else { return }
        if branch.isMerged {
            Task {
                _ = await state.model.deleteBranch(branch.name, force: false, snapshot: snapshot)
                await load()
                await state.refresh(directoryURL: directoryURL)
            }
        } else {
            state.branchPendingDelete = branch
        }
    }

    private func load() async {
        guard let snapshot else {
            isLoading = false
            return
        }
        isLoading = branches.isEmpty
        branches = await state.model.branches(snapshot: snapshot)
        isLoading = false
    }
}
