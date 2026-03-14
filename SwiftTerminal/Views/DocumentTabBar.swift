import SwiftUI
import UniformTypeIdentifiers

struct DocumentTabBar: View {
    let workspace: Workspace
    @State private var hoveredTabID: UUID?
    @State private var draggedTabID: UUID?
    @State private var renamingTab: TerminalTab?
    @State private var renameDraft = ""

    var body: some View {
        HStack(spacing: 5) {
            tabStrip
            addButton
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 3)
        .alert("Rename Tab", isPresented: isRenameAlertPresented) {
            TextField("Tab Name", text: $renameDraft)
            Button("Cancel", role: .cancel) {
                renamingTab = nil
            }
            Button("Rename") {
                commitRename()
            }
        } message: {
            Text("Set a custom name for this terminal tab.")
        }
    }

    private var tabStrip: some View {
        GeometryReader { proxy in
            let layout = tabLayout(for: proxy.size.width)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(workspace.tabs.enumerated()), id: \.element.id) { index, tab in
                        if index > 0 {
                            separator(before: index)
                        }
                        tabItem(tab, width: layout.tabWidth)
                    }
                }
                .frame(minWidth: layout.contentWidth, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
        .frame(height: 26)
        .padding(.top, 2)
        .padding(.horizontal, 2)
        .padding(.bottom, 0)
        .background(
            Capsule()
                .fill(.background.secondary)
        )
    }

    @ViewBuilder
    private func tabItem(_ tab: TerminalTab, width: CGFloat) -> some View {
        let isSelected = workspace.selectedTab === tab
        let isHovered = hoveredTabID == tab.id
        let isDragged = draggedTabID == tab.id

        Button {
            workspace.selectedTab = tab
        } label: {
            HStack(spacing: 0) {
                tabAccessoryPlaceholder

                Text(tab.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .center)

                tabAccessoryPlaceholder
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .frame(width: width)
            .background(
                Capsule()
                    .fill(backgroundStyle(isSelected: isSelected, isHovered: isHovered))
                    .strokeBorder(isSelected ? AnyShapeStyle(.separator) : AnyShapeStyle(.clear))
            )
            .contentShape(.capsule)
        }
        .opacity(isDragged ? 0.65 : 1)
        .animation(.snappy, value: workspace.tabs.map(\.id))
        .overlay(alignment: .leading) {
            closeButton(for: tab, isVisible: isHovered && workspace.tabs.count > 1)
                .padding(.leading, 10)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename") {
                beginRenaming(tab)
            }
        }
        .onDrag {
            draggedTabID = tab.id
            return NSItemProvider(object: tab.id.uuidString as NSString)
        }
        .onDrop(
            of: [UTType.text],
            delegate: TabDropDelegate(
                targetTab: tab,
                workspace: workspace,
                draggedTabID: $draggedTabID
            )
        )
        .onHover { isHovering in
            hoveredTabID = isHovering ? tab.id : (hoveredTabID == tab.id ? nil : hoveredTabID)
        }
    }

    private var addButton: some View {
        Button {
            openNewTab()
        } label: {
            Image(systemName: "plus")
        }
        .help("New Tab (\u{2318}T)")
        .controlSize(.large)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
    }

    private var tabAccessoryPlaceholder: some View {
        Color.clear
            .frame(width: 10, height: 10)
    }

    private func separator(before index: Int) -> some View {
        Rectangle()
            .fill(.separator)
            .frame(width: 1, height: 16)
            .padding(.horizontal, 2)
            .opacity(shouldShowSeparator(before: index) ? 1 : 0)
    }

    @ViewBuilder
    private func closeButton(for tab: TerminalTab, isVisible: Bool) -> some View {
        ZStack {
            if isVisible {
                Button {
                    closeTab(tab)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear
            }
        }
        .frame(width: 10, height: 10)
    }

    private func shouldShowSeparator(before index: Int) -> Bool {
        guard index > 0, index < workspace.tabs.count else { return false }

        let previousTab = workspace.tabs[index - 1]
        let currentTab = workspace.tabs[index]
        return workspace.selectedTab !== previousTab && workspace.selectedTab !== currentTab
    }

    private func backgroundStyle(isSelected: Bool, isHovered: Bool) -> AnyShapeStyle {
        if isSelected {
            return AnyShapeStyle(.quaternary)
        }

        if isHovered {
            return AnyShapeStyle(.quinary)
        }

        return AnyShapeStyle(.clear)
    }

    private func openNewTab() {
        withAnimation {
            _ = workspace.addTabFromSelectedDirectory()
        }
    }

    private func closeTab(_ tab: TerminalTab) {
        withAnimation {
            workspace.closeTab(tab)
        }
    }

    private func beginRenaming(_ tab: TerminalTab) {
        renamingTab = tab
        renameDraft = tab.title
    }

    private func commitRename() {
        renamingTab?.rename(to: renameDraft)
        renamingTab = nil
    }

    private var isRenameAlertPresented: Binding<Bool> {
        Binding(
            get: { renamingTab != nil },
            set: { isPresented in
                if !isPresented {
                    renamingTab = nil
                }
            }
        )
    }

    private func tabLayout(for availableWidth: CGFloat) -> (tabWidth: CGFloat, contentWidth: CGFloat) {
        let tabCount = max(workspace.tabs.count, 1)
        let separatorCount = max(workspace.tabs.count - 1, 0)
        let separatorWidth: CGFloat = 5
        let minimumTabWidth: CGFloat = 140
        let availableTabWidth = max(availableWidth - CGFloat(separatorCount) * separatorWidth, 0)
        let tabWidth = max(availableTabWidth / CGFloat(tabCount), minimumTabWidth)
        let contentWidth = CGFloat(tabCount) * tabWidth + CGFloat(separatorCount) * separatorWidth
        return (tabWidth, contentWidth)
    }
}

private struct TabDropDelegate: DropDelegate {
    let targetTab: TerminalTab
    let workspace: Workspace
    @Binding var draggedTabID: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggedTab = draggedTab,
              let targetIndex = workspace.tabs.firstIndex(of: targetTab) else { return }

        withAnimation(.snappy) {
            workspace.moveTab(draggedTab, to: targetIndex)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedTabID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {}

    private var draggedTab: TerminalTab? {
        guard let draggedTabID else { return nil }
        return workspace.tabs.first { $0.id == draggedTabID }
    }
}

