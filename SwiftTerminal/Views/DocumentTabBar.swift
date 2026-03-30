import SwiftUI
import UniformTypeIdentifiers

struct DocumentTabBar: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    let workspace: Workspace
    @State private var hoveredTabID: UUID?
    @State private var draggedTabID: UUID?
    @State private var renamingTab: Terminal?
    @State private var processNames: [UUID: String] = [:]

    var body: some View {
        HStack(spacing: 5) {
            tabStrip
            Button {
                let terminal = workspace.addTerminal(
                    currentDirectory: appState.selectedTerminal?.liveCurrentDirectory,
                    after: appState.selectedTerminal
                )
                appState.selectedTerminal = terminal
            } label: {
                Image(systemName: "plus")
                    .padding(2)
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
                for terminal in workspace.terminals {
                    if let name = terminal.foregroundProcessName {
                        names[terminal.id] = name
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
            let tabCount = max(workspace.terminals.count, 1)
            let separatorWidth: CGFloat = 5
            let totalSeparators = CGFloat(max(tabCount - 1, 0)) * separatorWidth
            let tabWidth = max((proxy.size.width - totalSeparators) / CGFloat(tabCount), 140)
            let contentWidth = CGFloat(tabCount) * tabWidth + totalSeparators

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(workspace.terminals.enumerated()), id: \.element.id) { index, terminal in
                        if index > 0 {
                            separator(before: index)
                        }
                        tabItem(terminal, width: tabWidth)
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
                .fill(colorScheme == .dark ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.fill.secondary))
        )
    }

    @ViewBuilder
    private func tabItem(_ terminal: Terminal, width: CGFloat) -> some View {
        let isSelected = appState.selectedTerminal === terminal
        let isHovered = hoveredTabID == terminal.id

        Button {
            appState.selectedTerminal = terminal
        } label: {
            HStack(spacing: 0) {
                Color.clear.frame(width: 10, height: 10)

                Text(processNames[terminal.id].map { "\(terminal.title) \u{2014} \($0)" } ?? terminal.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .center)

                if terminal.hasBellNotification {
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
        .animation(.default, value: workspace.terminals.map(\.id))
        .overlay(alignment: .leading) {
            if isHovered && workspace.terminals.count > 1 {
                Button {
                    closeTerminal(terminal)
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
                renamingTab = terminal
            } label: {
                Label("Rename", systemImage: "pencil")
            }
        }
        .onDrag {
            draggedTabID = terminal.id
            return NSItemProvider(object: terminal.id.uuidString as NSString)
        }
        .onDrop(
            of: [UTType.text],
            delegate: TabDropDelegate(
                targetTerminal: terminal,
                workspace: workspace,
                draggedTabID: $draggedTabID
            )
        )
        .onHover { isHovering in
            hoveredTabID = isHovering ? terminal.id : (hoveredTabID == terminal.id ? nil : hoveredTabID)
        }
    }

    private func separator(before index: Int) -> some View {
        let ordered = workspace.terminals
        let show = index > 0 && index < ordered.count
            && appState.selectedTerminal !== ordered[index - 1]
            && appState.selectedTerminal !== ordered[index]

        return Rectangle()
            .fill(.separator)
            .frame(width: 1, height: 16)
            .padding(.horizontal, 2)
            .opacity(show ? 1 : 0)
    }

    private func closeTerminal(_ terminal: Terminal) {
        if appState.selectedTerminal === terminal {
            // Select an adjacent terminal
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
        workspace.closeTerminal(terminal)
    }
}

private struct TabDropDelegate: DropDelegate {
    let targetTerminal: Terminal
    let workspace: Workspace
    @Binding var draggedTabID: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggedTabID,
              let draggedTerminal = workspace.terminals.first(where: { $0.id == draggedTabID }),
              let targetIndex = workspace.terminals.firstIndex(where: { $0 === targetTerminal }) else { return }

        withAnimation {
            // Swap sort orders
            let draggedOrder = draggedTerminal.sortOrder
            draggedTerminal.sortOrder = targetTerminal.sortOrder
            targetTerminal.sortOrder = draggedOrder
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedTabID = nil
        // Normalize sort orders
        for (i, terminal) in workspace.terminals.enumerated() {
            terminal.sortOrder = i
        }
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {}
}
