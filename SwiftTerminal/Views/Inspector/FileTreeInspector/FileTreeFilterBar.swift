import SwiftUI

struct FileTreeFilterBar: View {
    @Binding var searchText: String
    @Binding var showChangedOnly: Bool
    @Binding var showHiddenFiles: Bool
    var onToggleChanged: () -> Void

    var body: some View {
        FilterField(text: $searchText) {
//            Button {
//                showHiddenFiles.toggle()
//            } label: {
//                Image(systemName: showHiddenFiles ? "eye.fill" : "eye.slash")
//                    .font(.caption)
//                    .foregroundStyle(showHiddenFiles ? Color.accentColor : .secondary)
//            }
//            .buttonStyle(.plain)
//            .help(showHiddenFiles ? "Hide hidden files" : "Show hidden files")

            Button(action: onToggleChanged) {
                Image(systemName: showChangedOnly ? "plusminus.circle.fill" : "plusminus.circle")
                    .foregroundStyle(showChangedOnly ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help("Show only git-changed files")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}
