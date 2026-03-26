import SwiftUI

enum FileTreeAction {
    case revealInFinder(URL)
    case moveToTrash(URL)
    case duplicate(URL)
    case newFile(URL)
    case newFolder(URL)
}

struct FileTreeContextMenu: View {
    let item: FileItem
    let onAction: (FileTreeAction) -> Void

    private var parentURL: URL {
        item.isDirectory ? item.url : item.url.deletingLastPathComponent()
    }

    var body: some View {
        Button { onAction(.revealInFinder(item.url)) } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }

        Divider()

        Button { onAction(.moveToTrash(item.url)) } label: {
            Label("Move to Trash", systemImage: "trash")
        }

        Button { onAction(.duplicate(item.url)) } label: {
            Label("Duplicate", systemImage: "doc.on.doc")
        }

        Divider()

        Button { onAction(.newFile(parentURL)) } label: {
            Label("New File", systemImage: "doc.badge.plus")
        }

        Button { onAction(.newFolder(parentURL)) } label: {
            Label("New Folder", systemImage: "folder.badge.plus")
        }
    }
}
