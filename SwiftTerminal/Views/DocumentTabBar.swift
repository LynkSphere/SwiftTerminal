#if os(macOS)
import SwiftUI

struct DocumentTabBar: View {
    @Bindable var workspace: Workspace

    var body: some View {
        HStack(spacing: 8) {
            tabStrip
            addButton
        }
        .padding(.horizontal, 5)
        .padding(.bottom, 3)
    }

    private var tabStrip: some View {
        HStack(spacing: 2) {
            ForEach(workspace.tabs) { tab in
                tabItem(tab)
            }
        }
        .padding(2)
        .background(
            Capsule()
                .fill(.background.quinary)
        )
    }

    private func tabItem(_ tab: TerminalTab) -> some View {
        let isSelected = workspace.selectedTab === tab

        return HStack(spacing: 6) {
            Text(tab.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)

            if workspace.tabs.count > 1 {
                Button {
                    workspace.closeTab(tab)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            Capsule()
                .fill(isSelected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
                .shadow(color: .black.opacity(isSelected ? 0.15 : 0), radius: 2, y: 1)
        )
        .contentShape(Capsule())
        .onTapGesture {
            workspace.selectedTab = tab
        }
    }

    private var addButton: some View {
        Button {
            workspace.addTab()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
}
#endif
