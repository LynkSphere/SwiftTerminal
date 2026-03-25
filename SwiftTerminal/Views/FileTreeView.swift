import SwiftUI

struct FileTreeView: View {
    let directoryURL: URL

    @State private var items: [FileItem] = []

    var body: some View {
        List(items, children: \.children) { item in
            Label {
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(nsImage: item.icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            .listRowSeparator(.hidden)
        }
        .scrollContentBackground(.hidden)
        .task(id: directoryURL) {
            items = FileItem.buildTree(at: directoryURL)
        }
    }
}
