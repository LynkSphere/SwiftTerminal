import SwiftUI

struct FileNodeView: View {
    let item: FileItem
    @Binding var expandedIDs: Set<String>

    var body: some View {
        if let children = item.children {
            DisclosureGroup(isExpanded: Binding(
                get: { expandedIDs.contains(item.id) },
                set: { newValue in
                    if newValue {
                        expandedIDs.insert(item.id)
                    } else {
                        expandedIDs.remove(item.id)
                    }
                }
            )) {
                ForEach(children) { child in
                    FileNodeView(item: child, expandedIDs: $expandedIDs)
                        .tag(child.id)
                }
            } label: {
                FileRowView(item: item)
            }
            .listRowSeparator(.hidden)
        } else {
            FileRowView(item: item)
                .tag(item.id)
                .listRowSeparator(.hidden)
        }
    }
}
