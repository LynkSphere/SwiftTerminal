import SwiftUI

struct DocumentTabBar: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("hideTabBarWithSingleTab") private var hideTabBarWithSingleTab = false
    let workspace: Workspace
    @State private var hoveredTabID: UUID?
    @State private var dragModel = TabDragViewModel()
    @State private var renamingTab: Terminal?
    @State private var hoveredCloseTabID: UUID?

    var body: some View {
        let terminals = workspace.terminals
        let isVisible = terminals.count > 1 || (terminals.count == 1 && !hideTabBarWithSingleTab)
        tabContent(terminals: terminals)
            .frame(height: isVisible ? nil : 0)
            .opacity(isVisible ? 1 : 0)
            .allowsHitTesting(isVisible)
    }

    @ViewBuilder
    private func tabContent(terminals: [Terminal]) -> some View {
        HStack(spacing: 5) {
            tabStrip(terminals: terminals)
            Button("New Tab", systemImage: "plus") {
                let terminal = workspace.addTerminal(
                    currentDirectory: appState.selectedTerminal?.currentDirectory,
                    after: appState.selectedTerminal
                )
                appState.selectedTerminal = terminal
            }
            .labelStyle(.iconOnly)
            .help("New Tab")
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
            Text("Set a custom name for this terminal tab.")
        }
    }

    private func tabStrip(terminals: [Terminal]) -> some View {
        GeometryReader { proxy in
            let tabCount = max(terminals.count, 1)
            let separatorWidth: CGFloat = 5
            let totalSeparators = CGFloat(max(tabCount - 1, 0)) * separatorWidth
            let tabWidth = max((proxy.size.width - totalSeparators) / CGFloat(tabCount), 90)
            let contentWidth = CGFloat(tabCount) * tabWidth + totalSeparators
            let tabStride = tabWidth + separatorWidth

            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(terminals.enumerated(), id: \.element.id) { index, terminal in
                        if index > 0 {
                            separator(before: index, in: terminals)
                        }
                        tabItem(terminal, index: index, width: tabWidth, tabStride: tabStride, in: terminals)
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
    private func tabItem(_ terminal: Terminal, index: Int, width: CGFloat, tabStride: CGFloat, in terminals: [Terminal]) -> some View {
        let isSelected = appState.selectedTerminal === terminal
        let isHovered = hoveredTabID == terminal.id
        let isDragging = dragModel.draggedTabID == terminal.id
        let isFloating = isDragging && dragModel.isDetached
        let isMergeTarget = dragModel.mergeTargetID == terminal.id
        let computedOffset = dragModel.offset(
            for: terminal,
            at: index,
            tabStride: tabStride,
            tabCount: terminals.count
        )

        Button {
            appState.selectTabIfPresent(terminal, in: workspace)
        } label: {
            HStack(spacing: 0) {
                Color.clear.frame(width: 10, height: 10)

                Text(terminal.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .center)

                trailingIndicator(for: terminal)
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
        .animation(.default, value: terminals.count)
        .animation(.snappy(duration: 0.18), value: dragModel.isDetached)
        .animation(.snappy(duration: 0.18), value: dragModel.mergeTargetID)
        .animation(.snappy(duration: 0.18), value: dragModel.currentIndex)
        .overlay(alignment: .leading) {
            if isHovered && terminals.count > 1 && dragModel.draggedTabID == nil {
                Button("Close Tab", systemImage: "xmark") {
                    closeTerminal(terminal)
                }
                .labelStyle(.iconOnly)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .background(
                    Circle()
                        .fill(hoveredCloseTabID == terminal.id ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
                )
                .contentShape(.circle)
                .buttonStyle(.plain)
                .onHover { isHovering in
                    hoveredCloseTabID = isHovering ? terminal.id : (hoveredCloseTabID == terminal.id ? nil : hoveredCloseTabID)
                }
                .padding(.leading, 6)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename", systemImage: "pencil") {
                renamingTab = terminal
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .named("tabStrip"))
                .onChanged { value in
                    dragModel.update(
                        terminal: terminal,
                        translation: value.translation,
                        location: value.location,
                        tabWidth: width,
                        tabStride: tabStride,
                        terminals: terminals
                    )
                }
                .onEnded { _ in
                    dragModel.finish(in: workspace, using: appState)
                }
        )
        .help("Drag sideways to reorder. Pull down, then drop on another tab to merge.")
        .onHover { isHovering in
            hoveredTabID = isHovering ? terminal.id : (hoveredTabID == terminal.id ? nil : hoveredTabID)
        }
    }

    /// Trailing-edge status pip for a tab. Only renders when the running
    /// command actively reports progress via OSC 9;4 — being merely "busy"
    /// (foreground process alive, e.g. `man`, `vim`, `sleep`) is not enough,
    /// so the spinner stays out of interactive sessions. The bell dot
    /// overlays the progress circle so both can show simultaneously.
    @ViewBuilder
    private func trailingIndicator(for terminal: Terminal) -> some View {
        Group {
            if terminal.hasBellNotification {
                Circle()
                    .fill(.orange)
                    .frame(width: 6, height: 6)
            } else if let value = terminal.progressValue, terminal.progressState != .indeterminate {
                if value >= 100 {
                    Circle()
                        .fill(.secondary)
                        .frame(width: 6, height: 6)
                } else {
                    ProgressView(value: Double(value), total: 100)
                        .progressViewStyle(.circular)
                        .controlSize(.mini)
                        .tint(terminal.progressState == .error ? .red : nil)
                }
            } else if terminal.progressState == .indeterminate {
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

    private func separator(before index: Int, in terminals: [Terminal]) -> some View {
        let show = index > 0 && index < terminals.count
            && appState.selectedTerminal !== terminals[index - 1]
            && appState.selectedTerminal !== terminals[index]

        return Rectangle()
            .fill(.separator)
            .frame(width: 1, height: 16)
            .padding(.horizontal, 2)
            .opacity(show ? 1 : 0)
    }

    private func closeTerminal(_ terminal: Terminal) {
        if appState.paneTerminals(for: terminal).contains(where: { $0.hasChildProcess }) {
            appState.terminalPendingClose = terminal
            return
        }
        performClose(terminal)
    }

    private func performClose(_ terminal: Terminal) {
        if appState.selectedTerminal === terminal {
            let terminals = workspace.terminals
            if let idx = terminals.firstIndex(where: { $0 === terminal }) {
                if idx + 1 < terminals.count {
                    appState.selectedTerminal = terminals[idx + 1]
                } else if idx > 0 {
                    appState.selectedTerminal = terminals[idx - 1]
                } else {
                    appState.selectedTerminal = nil
                }
            }
        }
        appState.tearDownPanes(for: terminal)
        workspace.closeTerminal(terminal)
    }
}
