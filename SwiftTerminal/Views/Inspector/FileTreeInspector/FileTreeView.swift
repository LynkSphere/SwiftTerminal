import SwiftUI

struct FileTreeView: View {
    let directoryURL: URL
    @Bindable var state: FileTreeInspectorState

    @Environment(EditorPanel.self) private var editorPanel
    @AppStorage("showHiddenFiles") private var showHiddenFiles = false

    var body: some View {
        List(selection: $state.selectedID) {
            ForEach(state.model.displayItems) { item in
                FileNodeView(item: item)
                    .tag(item.id)
            }
        }
        .environment(state)
        .environment(\.fileTreeAction, handleAction)
        .scrollContentBackground(.hidden)
        .contextMenu {
            Button { handleAction(.newFile(directoryURL)) } label: {
                Label("New File", systemImage: "doc.badge.plus")
            }
            Button { handleAction(.newFolder(directoryURL)) } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
            Divider()
            Toggle("Show Hidden Files", isOn: $showHiddenFiles)
        }
        .safeAreaBar(edge: .bottom) {
            SearchBar(
                text: $state.model.searchText,
                placeholder: "Search for Files",
                focusTrigger: state.searchFocusTrigger,
                onSubmit: submitSearch
            ) {
                Button(action: toggleChangedFilter) {
                    Image(systemName: state.model.showChangedOnly ? "plusminus.circle.fill" : "plusminus.circle")
                        .foregroundStyle(state.model.showChangedOnly ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help("Show only git-changed files")
            }
            .padding(11)
        }
        .task(id: directoryURL) {
            state.model.showHiddenFiles = showHiddenFiles
            state.model.load(directoryURL: directoryURL)
            await state.model.refreshGit(directoryURL: directoryURL)
        }
        .gitPolling(id: directoryURL) {
            await state.model.refreshGit(directoryURL: directoryURL)
        }
        .onChange(of: state.model.submittedSearchText) { oldValue, newValue in
            if !newValue.isEmpty && oldValue.isEmpty {
                if state.savedExpandedIDs == nil {
                    state.savedExpandedIDs = state.expandedIDs
                }
                expandAllFolders(in: state.model.displayItems)
            } else if !newValue.isEmpty {
                expandAllFolders(in: state.model.displayItems)
            } else if newValue.isEmpty && !oldValue.isEmpty && !state.model.showChangedOnly {
                if let saved = state.savedExpandedIDs {
                    state.expandedIDs = saved
                    state.savedExpandedIDs = nil
                }
            }
        }
        .onChange(of: showHiddenFiles) {
            state.model.showHiddenFiles = showHiddenFiles
            state.model.load(directoryURL: directoryURL)
        }
        .onChange(of: state.selectedID) { _, newID in
            guard let id = newID,
                  let item = state.model.findItem(id: id),
                  !item.isDirectory
            else { return }
            editorPanel.openFile(item.url)
        }
    }

    private func toggleChangedFilter() {
        if !state.model.showChangedOnly {
            if state.savedExpandedIDs == nil {
                state.savedExpandedIDs = state.expandedIDs
            }
            expandAllFolders(in: state.model.displayItems)
        } else if state.model.submittedSearchText.isEmpty, let saved = state.savedExpandedIDs {
            state.expandedIDs = saved
            state.savedExpandedIDs = nil
        }
        state.model.showChangedOnly.toggle()
    }

    private func submitSearch() {
        state.model.submitSearch()
    }

    private func expandAllFolders(in items: [FileItem]) {
        for item in items {
            if item.children != nil {
                state.expandedIDs.insert(item.id)
                if let children = item.children {
                    expandAllFolders(in: children)
                }
            }
        }
    }

    // MARK: - Actions

    private func handleAction(_ action: FileTreeAction) {
        switch action {
        case .openFile(let url):
            editorPanel.openFile(url)

        case .revealInFinder(let url):
            NSWorkspace.shared.activateFileViewerSelecting([url])

        case .rename(let item):
            state.renamingID = item.id

        case .commitRename(let item, let newName):
            state.renamingID = nil
            if let newURL = state.model.rename(url: item.url, to: newName, directoryURL: directoryURL) {
                state.selectedID = newURL.path
            }

        case .moveToTrash(let url):
            state.model.moveToTrash(url: url, directoryURL: directoryURL)

        case .duplicate(let url):
            state.model.duplicate(url: url, directoryURL: directoryURL)

        case .newFile(let parentURL):
            let fileURL = state.model.createNewFile(in: parentURL, directoryURL: directoryURL)
            state.expandedIDs.insert(parentURL.path)
            state.selectedID = fileURL.path
            state.renamingID = fileURL.path

        case .newFolder(let parentURL):
            let folderURL = state.model.createNewFolder(in: parentURL, directoryURL: directoryURL)
            state.expandedIDs.insert(parentURL.path)
            state.selectedID = folderURL.path
            state.renamingID = folderURL.path
        }
    }
}
