import SwiftUI

struct WorkspaceTabBar: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("hideTabBarWithSingleTab") private var hideTabBarWithSingleTab = false
    let workspace: Workspace
    @State private var hoveredTabID: UUID?
    @State private var dragModel = TabDragViewModel()
    @State private var renamingTab: WorkspaceTab?
    @State private var hoveredCloseTabID: UUID?

    var body: some View {
        let tabs = workspace.tabs
        let isVisible = tabs.count > 1 || (tabs.count == 1 && !hideTabBarWithSingleTab)
        tabContent(tabs: tabs)
            .frame(height: isVisible ? nil : 0)
            .opacity(isVisible ? 1 : 0)
            .allowsHitTesting(isVisible)
    }

    @ViewBuilder
    private func tabContent(tabs: [WorkspaceTab]) -> some View {
        HStack(spacing: 5) {
            tabStrip(tabs: tabs)

            Button("New Tab", systemImage: "plus", action: newTerminal)
            .labelStyle(.iconOnly)
            .help("New terminal tab")
            .controlSize(.large)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 3)
        .alert("Rename Tab", isPresented: Binding(get: { renamingTab != nil }, set: { if !$0 { renamingTab = nil } }), presenting: renamingTab) { tab in
            TextField("Tab Name", text: Bindable(tab).title)
            Button("Cancel", role: .cancel) { renamingTab = nil }
            Button("Done", role: .confirm) { renamingTab = nil }
        } message: { _ in
            Text("Set a custom name for this tab.")
        }
    }

    private func newTerminal() {
        let tab = workspace.addTerminal(
            currentDirectory: appState.selectedPane?.terminal?.currentDirectory,
            after: appState.selectedTab
        )
        appState.selectedTab = tab
    }

    private func tabStrip(tabs: [WorkspaceTab]) -> some View {
        GeometryReader { proxy in
            let tabCount = max(tabs.count, 1)
            let separatorWidth: CGFloat = 5
            let totalSeparators = CGFloat(max(tabCount - 1, 0)) * separatorWidth
            let tabWidth = max((proxy.size.width - totalSeparators) / CGFloat(tabCount), 90)
            let contentWidth = CGFloat(tabCount) * tabWidth + totalSeparators
            let tabStride = tabWidth + separatorWidth

            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(tabs.enumerated(), id: \.element.id) { index, tab in
                        if index > 0 {
                            separator(before: index, in: tabs)
                        }
                        tabItem(tab, index: index, width: tabWidth, tabStride: tabStride, in: tabs)
                    }
                }
                .frame(minWidth: contentWidth, alignment: .leading)
                .coordinateSpace(name: "tabStrip")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
        .frame(height: 26)
        .padding(.top, 2)
        .padding(.horizontal, 2)
        .padding(.bottom, 0)
        .background(
            Capsule()
                .fill(colorScheme == .dark ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.fill.secondary))
        )
    }

    @ViewBuilder
    private func tabItem(_ tab: WorkspaceTab, index: Int, width: CGFloat, tabStride: CGFloat, in tabs: [WorkspaceTab]) -> some View {
        let isSelected = appState.selectedTab === tab
        let isHovered = hoveredTabID == tab.id
        let isDragging = dragModel.draggedTabID == tab.id
        let isFloating = isDragging && dragModel.isDetached
        let isMergeTarget = dragModel.mergeTargetID == tab.id
        let computedOffset = dragModel.offset(
            for: tab,
            at: index,
            tabStride: tabStride,
            tabCount: tabs.count
        )

        Button {
            appState.selectTabIfPresent(tab, in: workspace)
        } label: {
            HStack(spacing: 0) {
                Color.clear.frame(width: 10, height: 10)

                Text(tab.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .center)

                trailingIndicator(for: tab)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .frame(width: width)
            .background(
                Capsule()
                    .fill(tabBackground(isSelected: isSelected, isHovered: isHovered, isMergeTarget: isMergeTarget))
                    .strokeBorder(
                        isMergeTarget
                            ? AnyShapeStyle(.clear)
                            : isSelected
                                ? (colorScheme == .dark ? AnyShapeStyle(.separator) : AnyShapeStyle(.background))
                                : AnyShapeStyle(.clear),
                        lineWidth: 1
                    )
            )
            .contentShape(.capsule)
        }
        .offset(x: computedOffset.width, y: computedOffset.height)
        .scaleEffect(isFloating ? (dragModel.mergeTargetID == nil ? 0.98 : 0.92) : 1)
        .opacity(isFloating && dragModel.mergeTargetID != nil ? 0.78 : 1)
        .shadow(
            color: isFloating ? Color.black.opacity(0.18) : .clear,
            radius: isFloating ? 8 : 0,
            y: isFloating ? 4 : 0
        )
        .zIndex(isDragging ? 2 : isMergeTarget ? 1 : 0)
        .animation(.default, value: tabs.count)
        .animation(.snappy(duration: 0.18), value: dragModel.isDetached)
        .animation(.snappy(duration: 0.18), value: dragModel.mergeTargetID)
        .animation(.snappy(duration: 0.18), value: dragModel.currentIndex)
        .overlay(alignment: .leading) {
            if isHovered && tabs.count > 1 && dragModel.draggedTabID == nil {
                Button("Close Tab", systemImage: "xmark") {
                    appState.requestCloseTab(tab)
                }
                .labelStyle(.iconOnly)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .background(
                    Circle()
                        .fill(hoveredCloseTabID == tab.id ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
                )
                .contentShape(.circle)
                .buttonStyle(.plain)
                .onHover { isHovering in
                    hoveredCloseTabID = isHovering ? tab.id : (hoveredCloseTabID == tab.id ? nil : hoveredCloseTabID)
                }
                .padding(.leading, 6)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename", systemImage: "pencil") {
                renamingTab = tab
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .named("tabStrip"))
                .onChanged { value in
                    dragModel.update(
                        tab: tab,
                        translation: value.translation,
                        location: value.location,
                        tabWidth: width,
                        tabStride: tabStride,
                        tabs: tabs
                    )
                }
                .onEnded { _ in
                    dragModel.finish(in: workspace, using: appState)
                }
        )
        .help("Drag sideways to reorder. Pull down, then drop on another tab to merge.")
        .onHover { isHovering in
            hoveredTabID = isHovering ? tab.id : (hoveredTabID == tab.id ? nil : hoveredTabID)
        }
    }

    /// Trailing-edge status pip for a tab. Only renders when the running
    /// command actively reports progress via OSC 9;4 — being merely "busy"
    /// (foreground process alive, e.g. `man`, `vim`, `sleep`) is not enough,
    /// so the spinner stays out of interactive sessions. The bell dot
    /// overlays the progress circle so both can show simultaneously.
    @ViewBuilder
    private func trailingIndicator(for tab: WorkspaceTab) -> some View {
        Group {
            if tab.focusedPane.terminal?.hasBellNotification == true {
                Circle()
                    .fill(.orange)
                    .frame(width: 6, height: 6)
            } else if let value = tab.focusedPane.terminal?.progressValue, tab.focusedPane.terminal?.progressState != .indeterminate {
                if value >= 100 {
                    Circle()
                        .fill(.secondary)
                        .frame(width: 6, height: 6)
                } else {
                    ProgressView(value: Double(value), total: 100)
                        .progressViewStyle(.circular)
                        .controlSize(.mini)
                        .tint(tab.focusedPane.terminal?.progressState == .error ? .red : nil)
                }
            } else if tab.focusedPane.terminal?.progressState == .indeterminate {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Color.clear
            }
        }
        .frame(width: 12, height: 12)
    }

    private func tabBackground(isSelected: Bool, isHovered: Bool, isMergeTarget: Bool) -> AnyShapeStyle {
        if isMergeTarget {
            return AnyShapeStyle(Color.accentColor.opacity(colorScheme == .dark ? 0.24 : 0.12))
        }
        if isSelected {
            return colorScheme == .dark ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.background.secondary)
        }
        return isHovered ? AnyShapeStyle(.quinary) : AnyShapeStyle(.clear)
    }

    private func separator(before index: Int, in tabs: [WorkspaceTab]) -> some View {
        let show = index > 0 && index < tabs.count
            && appState.selectedTab !== tabs[index - 1]
            && appState.selectedTab !== tabs[index]

        return Rectangle()
            .fill(.separator)
            .frame(width: 1, height: 16)
            .padding(.horizontal, 2)
            .opacity(show ? 1 : 0)
    }

}
