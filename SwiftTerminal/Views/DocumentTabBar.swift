import SwiftUI
import UniformTypeIdentifiers

struct DocumentTabBar: View {
    @Environment(AppState.self) private var appState
    let workspace: Workspace
    @State private var hoveredTabID: UUID?
    @State private var draggedTabID: UUID?
    @State private var renamingTab: TerminalTab?
    @State private var processNames: [UUID: String] = [:]

    var body: some View {
        HStack(spacing: 5) {
            tabStrip
            Button {
                withAnimation {
                    _ = workspace.addTab(currentDirectory: workspace.selectedTab?.liveCurrentDirectory)
                }
            } label: {
                Image(systemName: "plus")
                    .padding(1)
            }
            .help("New Tab")
            .controlSize(.large)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 3)
        .task {
            while !Task.isCancelled {
                var names: [UUID: String] = [:]
                for tab in workspace.tabs {
                    if let name = tab.foregroundProcessName {
                        names[tab.id] = name
                    }
                }
                processNames = names
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .alert("Rename Tab", isPresented: Binding(get: { renamingTab != nil }, set: { if !$0 { renamingTab = nil } }), presenting: renamingTab) { tab in
            TextField("Tab Name", text: Bindable(tab).title)
            Button("Cancel", role: .cancel) { renamingTab = nil }
            Button("Done", role: .confirm) { renamingTab = nil }
        } message: { _ in
            Text("Set a custom name for this terminal tab.")
        }
    }

    private var tabStrip: some View {
        GeometryReader { proxy in
            let tabCount = max(workspace.tabs.count, 1)
            let separatorWidth: CGFloat = 5
            let totalSeparators = CGFloat(max(tabCount - 1, 0)) * separatorWidth
            let tabWidth = max((proxy.size.width - totalSeparators) / CGFloat(tabCount), 140)
            let contentWidth = CGFloat(tabCount) * tabWidth + totalSeparators

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(workspace.sortedTabs.enumerated()), id: \.element.id) { index, tab in
                        if index > 0 {
                            separator(before: index)
                        }
                        tabItem(tab, width: tabWidth)
                    }
                }
                .frame(minWidth: contentWidth, alignment: .leading)
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
                .fill(.background.tertiary)
        )
    }

    @ViewBuilder
    private func tabItem(_ tab: TerminalTab, width: CGFloat) -> some View {
        let isSelected = workspace.selectedTab === tab
        let isHovered = hoveredTabID == tab.id

        Button {
            workspace.selectedTab = tab
        } label: {
            HStack(spacing: 0) {
                Color.clear.frame(width: 10, height: 10)

                Text(processNames[tab.id].map { "\(tab.title) \u{2014} \($0)" } ?? tab.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .center)

                if !isSelected && tab.hasBellNotification {
                    Circle()
                        .fill(.orange)
                        .frame(width: 6, height: 6)
                        .frame(width: 10, height: 10)
                } else {
                    Color.clear.frame(width: 10, height: 10)
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .frame(width: width)
            .background(
                Capsule()
                    .fill(isSelected ? AnyShapeStyle(.quaternary) : isHovered ? AnyShapeStyle(.quinary) : AnyShapeStyle(.clear))
                    .strokeBorder(isSelected ? AnyShapeStyle(.separator) : AnyShapeStyle(.clear))
            )
            .contentShape(.capsule)
        }
        .animation(.default, value: workspace.sortedTabs.map(\.id))
        .overlay(alignment: .leading) {
            if isHovered && workspace.tabs.count > 1 {
                Button {
                    closeTab(tab)
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                }
                .controlSize(.small)
                .buttonBorderShape(.circle)
                .buttonStyle(.bordered)
                .padding(.leading, 5)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                renamingTab = tab
            } label: {
                Label("Rename", systemImage: "pencil")
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

    private func separator(before index: Int) -> some View {
        let ordered = workspace.sortedTabs
        let show = index > 0 && index < ordered.count
            && workspace.selectedTab !== ordered[index - 1]
            && workspace.selectedTab !== ordered[index]

        return Rectangle()
            .fill(.separator)
            .frame(width: 1, height: 16)
            .padding(.horizontal, 2)
            .opacity(show ? 1 : 0)
    }

    private func closeTab(_ tab: TerminalTab) {
        if tab.hasChildProcess {
            appState.tabToClose = tab
            appState.showCloseConfirmation = true
        } else {
            withAnimation {
                workspace.closeTab(tab)
            }
        }
    }
}

private struct TabDropDelegate: DropDelegate {
    let targetTab: TerminalTab
    let workspace: Workspace
    @Binding var draggedTabID: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggedTabID,
              let draggedTab = workspace.sortedTabs.first(where: { $0.id == draggedTabID }),
              let targetIndex = workspace.sortedTabs.firstIndex(of: targetTab) else { return }

        withAnimation {
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
}
