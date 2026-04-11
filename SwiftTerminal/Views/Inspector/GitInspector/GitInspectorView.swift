import SwiftUI

struct GitInspectorView: View {
    let directoryURL: URL
    @Bindable var state: GitInspectorState
    var onShowInFileTree: ((URL) -> Void)?

    private var snapshot: GitRepositoryStatusSnapshot? { state.currentSnapshot }

    var body: some View {
        GitInspectorChangesList(
            directoryURL: directoryURL,
            state: state,
            onShowInFileTree: onShowInFileTree
        )
        .safeAreaBar(edge: .top) {
            VStack(spacing: 8) {
                GitInspectorBranchBar(directoryURL: directoryURL, state: state)
                GitInspectorCommitArea(directoryURL: directoryURL, state: state)
                    .padding(.horizontal, 5)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .padding(.top, 7)
        }
        .safeAreaBar(edge: .bottom) {
            if state.model.snapshots.count > 1 {
                repoPicker.padding()
            }
        }
        .overlay {
            if state.model.isLoading && state.model.snapshots.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlay(alignment: .bottom) {
            if let error = state.model.errorMessage {
                errorBanner(error)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state.model.errorMessage)
        .task(id: directoryURL) {
            await state.refresh(directoryURL: directoryURL)
            if state.selectedRepoURL == nil {
                state.selectedRepoURL = state.model.snapshots.first?.repositoryRootURL
            }
        }
        .task(id: snapshot?.branchName) {
            guard let snapshot else { return }
            await state.model.fetch(snapshot: snapshot)
            await state.refresh(directoryURL: directoryURL)
        }
        .gitPolling(id: directoryURL) {
            await state.refresh(directoryURL: directoryURL)
        }
        .alert("Discard Changes?", isPresented: discardAlertBinding) {
            Button("Discard", role: .destructive) {
                guard let target = state.discardTarget else { return }
                state.performDiscard(target, directoryURL: directoryURL)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(discardAlertMessage)
        }
        .alert("Stash Changes?", isPresented: stashAlertBinding) {
            Button("Stash & Switch", role: .destructive) {
                state.confirmStashAndSwitch(directoryURL: directoryURL)
            }
            Button("Cancel", role: .cancel) { state.pendingBranchSwitch = nil }
        } message: {
            Text("You have uncommitted changes. Stash all changes (including staged and untracked) before switching branches?")
        }
        .alert("Stash All Changes", isPresented: $state.showStashAlert) {
            TextField("Stash name", text: $state.stashMessage)
            Button("Stash") {
                state.confirmStashAll(directoryURL: directoryURL)
            }
            Button("Cancel", role: .cancel) { state.stashMessage = "" }
        } message: {
            Text("Stash all staged, unstaged, and untracked changes.")
        }
        .sheet(isPresented: $state.showNewBranchSheet) {
            NewBranchSheet(directoryURL: directoryURL, state: state)
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
            EmptyView()
        }
        .pickerStyle(.menu)
        .controlSize(.large)
        .buttonSizing(.flexible)
    }

    // MARK: - Error Banner

    @ViewBuilder
    private func errorBanner(_ error: String) -> some View {
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

    // MARK: - Alert Bindings

    private var discardAlertBinding: Binding<Bool> {
        Binding(
            get: { state.discardTarget != nil },
            set: { if !$0 { state.discardTarget = nil } }
        )
    }

    private var stashAlertBinding: Binding<Bool> {
        Binding(
            get: { state.pendingBranchSwitch != nil },
            set: { if !$0 { state.pendingBranchSwitch = nil } }
        )
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
}
