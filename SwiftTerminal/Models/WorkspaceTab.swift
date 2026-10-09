import Foundation
import Observation

@MainActor @Observable
final class WorkspaceTab: Identifiable, Hashable {
    let id: UUID
    var title: String
    private(set) var layout: PaneNode
    private(set) var focusedPane: Pane
    @ObservationIgnored weak var workspace: Workspace?

    init(pane: Pane, workspace: Workspace) {
        id = UUID()
        title = ""
        layout = PaneNode(pane: pane)
        focusedPane = pane
        self.workspace = workspace
    }

    init(snapshot: TabSnapshot, workspace: Workspace) throws {
        id = snapshot.id
        title = snapshot.title
        let restored = try snapshot.layout.restore(in: workspace)
        let panes = restored.leafPanes
        guard let first = panes.first, Set(panes.map(\.id)).count == panes.count else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid tab panes"))
        }
        layout = restored
        focusedPane = panes.first { $0.id == snapshot.focusedPaneID } ?? first
        self.workspace = workspace
    }

    var panes: [Pane] { layout.leafPanes }
    var isSplit: Bool { !layout.isLeaf }
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? focusedPane.displayTitle : trimmed
    }

    func focus(_ pane: Pane) {
        guard panes.contains(where: { $0 === pane }) else { return }
        focusedPane = pane
        pane.terminal?.hasBellNotification = false
    }

    @discardableResult
    func split(_ pane: Pane, beside neighbor: Pane, axis: SplitAxis) -> Bool {
        guard pane.workspace === workspace,
              !panes.contains(where: { $0 === pane }),
              layout.split(targetID: neighbor.id, with: PaneNode(pane: pane), axis: axis) else { return false }
        focus(pane)
        return true
    }

    func merge(_ tab: WorkspaceTab, axis: SplitAxis) {
        layout = PaneNode(axis: axis, children: [layout, tab.layout])
        focus(tab.focusedPane)
    }

    @discardableResult
    func removePane(_ pane: Pane) -> Bool {
        let leaves = panes
        guard leaves.count > 1, let index = leaves.firstIndex(where: { $0 === pane }),
              layout.removeLeaf(targetID: pane.id) else { return false }
        if focusedPane === pane {
            focus(leaves[index + 1 < leaves.count ? index + 1 : index - 1])
        }
        return true
    }

    func close() {
        for pane in panes { pane.close() }
    }

    var snapshot: TabSnapshot? {
        guard let layout = layout.snapshot else { return nil }
        return TabSnapshot(id: id, title: title, layout: layout, focusedPaneID: focusedPane.id)
    }

    static func == (lhs: WorkspaceTab, rhs: WorkspaceTab) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct TabSnapshot: Codable {
    var id: UUID
    var title: String
    var layout: PaneLayoutSnapshot
    var focusedPaneID: UUID?
}

indirect enum PaneLayoutSnapshot: Codable {
    case terminal(Terminal)
    case split(axis: SplitAxis, children: [PaneLayoutSnapshot], fractions: [Double])

    func restore(in workspace: Workspace) throws -> PaneNode {
        switch self {
        case .terminal(let terminal):
            return PaneNode(pane: Pane(content: .terminal(terminal), workspace: workspace))
        case .split(let axis, let children, let fractions):
            let total = fractions.reduce(0, +)
            guard children.count >= 2, fractions.count == children.count,
                  fractions.allSatisfy({ $0.isFinite && $0 > 0 }), total.isFinite else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid split layout"))
            }
            return PaneNode(axis: axis, children: try children.map { try $0.restore(in: workspace) }, fractions: fractions.map { $0 / total })
        }
    }
}
