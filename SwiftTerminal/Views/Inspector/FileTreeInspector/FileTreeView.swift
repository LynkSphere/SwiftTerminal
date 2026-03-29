import SwiftUI

struct FileTreeView: View {
    let directoryURL: URL

    @Environment(EditorPanel.self) private var editorPanel
    @State private var model = FileTreeModel()
    @State private var selectedID: FileItem.ID?
    @State private var expandedIDs: Set<String> = []
    @State private var savedExpandedIDs: Set<String>?
    @AppStorage("showHiddenFiles") private var showHiddenFiles = false

    var body: some View {
        List(selection: $selectedID) {
            ForEach(model.displayItems) { item in
                FileNodeView(item: item, expandedIDs: $expandedIDs, onAction: handleAction)
                    .tag(item.id)
            }
        }
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
            SearchBar(text: $model.searchText, placeholder: "Search for Files") {
                Button(action: toggleChangedFilter) {
                    Image(systemName: model.showChangedOnly ? "plusminus.circle.fill" : "plusminus.circle")
                        .foregroundStyle(model.showChangedOnly ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help("Show only git-changed files")
            }
            .padding(11)
        }
        .task(id: directoryURL) {
            model.showHiddenFiles = showHiddenFiles
            model.load(directoryURL: directoryURL)
            await model.refreshGit(directoryURL: directoryURL)
        }
        .task(id: directoryURL, priority: .low) {
            await pollGitStatus()
        }
        .onChange(of: model.searchText) { oldValue, newValue in
            if !newValue.isEmpty && oldValue.isEmpty {
                // Starting a search — save expansion state and expand all
                if savedExpandedIDs == nil {
                    savedExpandedIDs = expandedIDs
                }
                expandAllFolders(in: model.displayItems)
            } else if !newValue.isEmpty {
                // Search text changed — expand all filtered results
                expandAllFolders(in: model.displayItems)
            } else if newValue.isEmpty && !oldValue.isEmpty && !model.showChangedOnly {
                // Search cleared and no other filter active — restore
                if let saved = savedExpandedIDs {
                    expandedIDs = saved
                    savedExpandedIDs = nil
                }
            }
        }
        .onChange(of: showHiddenFiles) {
            model.showHiddenFiles = showHiddenFiles
            model.load(directoryURL: directoryURL)
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
            if savedExpandedIDs == nil {
                savedExpandedIDs = expandedIDs
            }
            expandAllFolders(in: model.displayItems)
        } else if model.searchText.isEmpty, let saved = savedExpandedIDs {
            // Only restore if search is also inactive
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

    // MARK: - Context Menu Actions

    private func handleAction(_ action: FileTreeAction) {
        switch action {
        case .revealInFinder(let url):
            NSWorkspace.shared.activateFileViewerSelecting([url])

        case .moveToTrash(let url):
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
            model.load(directoryURL: directoryURL)

        case .duplicate(let url):
            let fm = FileManager.default
            let directory = url.deletingLastPathComponent()
            let name = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension
            var suffix = 2
            var destination: URL
            repeat {
                let newName = ext.isEmpty ? "\(name) \(suffix)" : "\(name) \(suffix).\(ext)"
                destination = directory.appendingPathComponent(newName)
                suffix += 1
            } while fm.fileExists(atPath: destination.path)
            try? fm.copyItem(at: url, to: destination)
            model.load(directoryURL: directoryURL)

        case .newFile(let parentURL):
            let fm = FileManager.default
            var destination = parentURL.appendingPathComponent("Untitled")
            var suffix = 2
            while fm.fileExists(atPath: destination.path) {
                destination = parentURL.appendingPathComponent("Untitled \(suffix)")
                suffix += 1
            }
            fm.createFile(atPath: destination.path, contents: nil)
            model.load(directoryURL: directoryURL)
            expandedIDs.insert(parentURL.path)

        case .newFolder(let parentURL):
            let fm = FileManager.default
            var destination = parentURL.appendingPathComponent("New Folder")
            var suffix = 2
            while fm.fileExists(atPath: destination.path) {
                destination = parentURL.appendingPathComponent("New Folder \(suffix)")
                suffix += 1
            }
            try? fm.createDirectory(at: destination, withIntermediateDirectories: false)
            model.load(directoryURL: directoryURL)
            expandedIDs.insert(parentURL.path)
        }
    }
}
