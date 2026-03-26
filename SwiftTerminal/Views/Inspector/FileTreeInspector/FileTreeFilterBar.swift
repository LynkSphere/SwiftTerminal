import SwiftUI

struct FileTreeFilterBar: View {
    @Binding var searchText: String
    @Binding var showChangedOnly: Bool
    var onToggleChanged: () -> Void

    var body: some View {
        FilterField(text: $searchText) {
            Button(action: onToggleChanged) {
                Image(systemName: showChangedOnly ? "externaldrive.fill.badge.checkmark" : "externaldrive.badge.checkmark")
                    .font(.caption)
                    .foregroundStyle(showChangedOnly ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help("Show only git-changed files")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}
