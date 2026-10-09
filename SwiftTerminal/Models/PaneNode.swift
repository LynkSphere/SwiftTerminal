import SwiftUI

@MainActor @Observable
final class PaneNode: Identifiable {
    let id = UUID()

    /// Non-nil iff this node is a leaf.
    var pane: Pane?

    var axis: SplitAxis
    var children: [PaneNode]
    /// Each child's fraction of the branch's length along `axis`; sums to ~1.
    var fractions: [Double]

    init(pane: Pane) {
        self.pane = pane
        self.axis = .horizontal
        self.children = []
        self.fractions = []
    }

    init(axis: SplitAxis, children: [PaneNode], fractions: [Double]? = nil) {
        self.pane = nil
        self.axis = axis
        self.children = children
        if let fractions, fractions.count == children.count {
            self.fractions = fractions
        } else {
            let n = max(children.count, 1)
            self.fractions = Array(repeating: 1.0 / Double(n), count: children.count)
        }
    }

    var isLeaf: Bool { pane != nil }

    /// All panes at the leaves, left-to-right / top-to-bottom.
    var leafPanes: [Pane] {
        if let pane { return [pane] }
        return children.flatMap { $0.leafPanes }
    }

    /// The branch directly containing `paneID`'s leaf and its child index.
    func parent(of paneID: UUID) -> (branch: PaneNode, index: Int)? {
        for (i, child) in children.enumerated() {
            if child.pane?.id == paneID { return (self, i) }
            if let found = child.parent(of: paneID) { return found }
        }
        return nil
    }

    // MARK: - Mutations

    /// Inserts `newLeaf` next to `targetID` along `axis`. When the target's parent
    /// already runs along `axis` the pane joins as a sibling (even N-way split,
    /// neighbors untouched); otherwise the target leaf becomes a 50/50 branch.
    @discardableResult
    func split(targetID: UUID, with newLeaf: PaneNode, axis: SplitAxis) -> Bool {
        if let (branch, idx) = parent(of: targetID) {
            if branch.axis == axis {
                let f = branch.fractions[idx]
                branch.fractions[idx] = f / 2
                branch.fractions.insert(f / 2, at: idx + 1)
                branch.children.insert(newLeaf, at: idx + 1)
            } else {
                convertLeafToBranch(branch.children[idx], adding: newLeaf, axis: axis)
            }
            return true
        }
        if pane?.id == targetID {
            convertLeafToBranch(self, adding: newLeaf, axis: axis)
            return true
        }
        return false
    }

    private func convertLeafToBranch(_ leaf: PaneNode, adding newLeaf: PaneNode, axis: SplitAxis) {
        guard let term = leaf.pane else { return }
        let moved = PaneNode(pane: term)
        leaf.pane = nil
        leaf.axis = axis
        leaf.children = [moved, newLeaf]
        leaf.fractions = [0.5, 0.5]
    }

    /// Removes the leaf for `targetID`, redistributing its space to siblings and
    /// collapsing any branch left with a single child. Returns false if absent.
    @discardableResult
    func removeLeaf(targetID: UUID) -> Bool {
        guard let (branch, idx) = parent(of: targetID) else { return false }
        let freed = branch.fractions[idx]
        branch.children.remove(at: idx)
        branch.fractions.remove(at: idx)
        let total = branch.fractions.reduce(0, +)
        if total > 0 {
            branch.fractions = branch.fractions.map { $0 + freed * ($0 / total) }
        }
        collapse()
        return true
    }

    /// Flattens redundant single-child branches, bottom-up, including self.
    private func collapse() {
        guard !isLeaf else { return }
        for child in children { child.collapse() }

        if children.count == 1, let only = children.first {
            pane = only.pane
            axis = only.axis
            fractions = only.fractions
            children = only.children
        }
    }

    var snapshot: PaneLayoutSnapshot? {
        if let pane { return pane.terminal.map(PaneLayoutSnapshot.terminal) }
        let saved = children.enumerated().compactMap { index, child in
            child.snapshot.map { (layout: $0, fraction: fractions[index]) }
        }
        if saved.count == 1 { return saved[0].layout }
        guard !saved.isEmpty else { return nil }
        let total = saved.reduce(0) { $0 + $1.fraction }
        return .split(axis: axis, children: saved.map(\.layout), fractions: saved.map { $0.fraction / total })
    }
}
