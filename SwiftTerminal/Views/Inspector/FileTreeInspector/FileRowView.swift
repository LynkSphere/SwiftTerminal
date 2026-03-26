import SwiftUI

struct FileRowView: View {
    let item: FileItem

    var body: some View {
        FileLabel(name: item.name, icon: item.icon) {
            if let status = item.gitStatus {
                Text(status.statusSymbol)
                    .font(.caption2.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(item.isHidden ? 0.5 : 1)
    }
}
