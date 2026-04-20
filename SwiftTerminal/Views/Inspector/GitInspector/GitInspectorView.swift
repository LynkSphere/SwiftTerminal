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
            .padding(.top, 13)
        }
        .safeAreaBar(edge: .bottom) {
            VStack {
                if let banner = activeBanner {
                    bannerView(banner)
                        .transition(.move(edge: .bottom))
                }
                if state.model.snapshots.count > 1 {
                    repoPicker
                }
            }
            .padding()
            .animation(.easeInOut(duration: 0.2), value: activeBanner)
        }
        .overlay {
            if state.model.isLoading && state.model.snapshots.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
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
        .watchFileSystem(at: directoryURL) {
            Task { await state.refresh(directoryURL: directoryURL) }
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
        .alert("Publish Branch?", isPresented: $state.showPushUpstreamAlert) {
            Button("Publish") {
                state.pushSetUpstream(directoryURL: directoryURL)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The branch \"\(snapshot?.branchName ?? "")\" does not exist on the remote. This will create a new branch on the remote and push your commits.")
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

    // MARK: - Banner

    private enum BannerKind: Equatable {
        case success(String)
        case error(String)
    }

    private var activeBanner: BannerKind? {
        if let error = state.model.errorMessage { return .error(error) }
        if let success = state.model.successMessage { return .success(success) }
        return nil
    }

    @ViewBuilder
    private func bannerView(_ banner: BannerKind) -> some View {
        let (icon, iconColor, message): (String, Color, String) = switch banner {
        case .error(let msg): ("exclamationmark.triangle.fill", .yellow, msg)
        case .success(let msg): ("checkmark.circle.fill", .green, msg)
        }
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
            Text(message)
                .lineLimit(3)
            Spacer()
            Button {
                dismissBanner(banner)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .font(.caption)
        .padding(8)
        .padding(.horizontal, 2)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        .task(id: banner) {
            let seconds: Int = if case .success = banner { 3 } else { 5 }
            try? await Task.sleep(for: .seconds(seconds))
            dismissBanner(banner)
        }
    }

    private func dismissBanner(_ banner: BannerKind) {
        switch banner {
        case .error(let msg):
            if state.model.errorMessage == msg { state.model.errorMessage = nil }
        case .success(let msg):
            if state.model.successMessage == msg { state.model.successMessage = nil }
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
