import SwiftUI

struct FileTreeView: View {
    let directoryURL: URL

    @Environment(EditorPanel.self) private var editorPanel
    @State private var model = FileTreeModel()
    @State private var selectedID: FileItem.ID?
    @State private var expandedIDs: Set<String> = []
    @State private var savedExpandedIDs: Set<String>?

    var body: some View {
        List(selection: $selectedID) {
            ForEach(model.displayItems) { item in
                FileNodeView(item: item, expandedIDs: $expandedIDs)
                    .tag(item.id)
            }
        }
        .scrollContentBackground(.hidden)
        .safeAreaBar(edge: .bottom) {
            FileTreeFilterBar(
                searchText: $model.searchText,
                showChangedOnly: $model.showChangedOnly,
                onToggleChanged: toggleChangedFilter
            )
        }
        .task(id: directoryURL) {
            model.load(directoryURL: directoryURL)
            await model.refreshGit(directoryURL: directoryURL)
        }
        .task(id: directoryURL, priority: .low) {
            await pollGitStatus()
        }
        .onChange(of: selectedID) { _, newID in
            guard let id = newID,
                  let item = model.findItem(id: id),
                  !item.isDirectory
            else { return }
            editorPanel.openFile(item.url)
        }
    }

    private func pollGitStatus() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { break }
            await model.refreshGit(directoryURL: directoryURL)
        }
    }

    private func toggleChangedFilter() {
        if !model.showChangedOnly {
            savedExpandedIDs = expandedIDs
            expandAllFolders(in: model.displayItems)
        } else if let saved = savedExpandedIDs {
            expandedIDs = saved
            savedExpandedIDs = nil
        }
        model.showChangedOnly.toggle()
    }

    private func expandAllFolders(in items: [FileItem]) {
        for item in items {
            if item.children != nil {
                expandedIDs.insert(item.id)
                if let children = item.children {
                    expandAllFolders(in: children)
                }
            }
        }
    }
}
