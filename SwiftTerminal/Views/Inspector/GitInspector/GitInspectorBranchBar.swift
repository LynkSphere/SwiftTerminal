import SwiftUI

struct GitInspectorBranchBar: View {
    let directoryURL: URL
    @Bindable var state: GitInspectorState

    private var snapshot: GitRepositoryStatusSnapshot? { state.currentSnapshot }

    var body: some View {
        HStack(spacing: 4) {
            branchPicker
            Spacer()
            if state.model.isBusy {
                ProgressView()
                    .controlSize(.mini)
            }
            menuButton
        }
    }

    private var branchPicker: some View {
        Menu {
            if let snapshot {
                ForEach(snapshot.localBranches, id: \.self) { branch in
                    Button {
                        state.switchBranch(to: branch, directoryURL: directoryURL, snapshot: snapshot)
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
                Text(snapshot?.branchName ?? "No Branch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "arrow.triangle.branch")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
    }

    private var menuButton: some View {
        Menu {
            Button {
                state.newBranchName = ""
                state.showNewBranchSheet = true
            } label: {
                Label("New Branch", systemImage: "plus")
            }

            Divider()

            Button {
                state.stashMessage = ""
                state.showStashAlert = true
            } label: {
                Label("Stash All...", systemImage: "tray.and.arrow.down")
            }
            .disabled(snapshot?.isDirty != true)

            Button {
                state.applyLatestStash(directoryURL: directoryURL)
            } label: {
                Label("Apply Stash", systemImage: "tray.and.arrow.up")
            }

            Divider()

            Button {
                state.fetch(directoryURL: directoryURL)
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

struct NewBranchSheet: View {
    let directoryURL: URL
    @Bindable var state: GitInspectorState

    var body: some View {
        VStack(spacing: 12) {
            Text("New Branch")
                .font(.headline)

            Text("Create a new branch from \"\(state.currentSnapshot?.branchName ?? "HEAD")\"")
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
                    state.showNewBranchSheet = false
                    state.createBranch(named: state.newBranchName, directoryURL: directoryURL)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(state.newBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
    }
}
