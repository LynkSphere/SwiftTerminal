import AppKit
import UniformTypeIdentifiers

struct FileItem: Identifiable, Hashable {
    var id: String { url.path }
    let name: String
    let url: URL
    let isDirectory: Bool
    var children: [FileItem]?

    var icon: NSImage {
        if isDirectory {
            return NSWorkspace.shared.icon(for: .folder)
        }
        let type = UTType(filenameExtension: url.pathExtension.lowercased()) ?? .data
        return NSWorkspace.shared.icon(for: type)
    }

    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.url == rhs.url
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }

    static func buildTree(at directoryURL: URL) -> [FileItem] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents
            .filter { !ignoredNames.contains($0.lastPathComponent) }
            .compactMap { url -> FileItem? in
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                let isDir = values?.isDirectory ?? false
                return FileItem(
                    name: url.lastPathComponent,
                    url: url,
                    isDirectory: isDir,
                    children: isDir ? buildTree(at: url) : nil
                )
            }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private static let ignoredNames: Set<String> = [
        ".DS_Store", ".git", "node_modules", ".build", "DerivedData",
        "Pods", "__pycache__", ".venv", "venv", ".svn", ".hg",
    ]
}
