import SwiftUI

/// `horizontal`: children side by side. `vertical`: children stacked.
enum SplitAxis: Equatable {
    case horizontal
    case vertical
}

enum PaneFocusDirection {
    case left, right, up, down
}

/// A node in a tab's split layout: either a *leaf* (one `Terminal`) or a *branch*
/// (laying out `children` along `axis`). The tab's representative `Terminal` is
/// always one of the leaves. Session-only; never encoded.
@Observable
final class PaneNode: Identifiable {
    let id = UUID()

    /// Non-nil iff this node is a leaf.
    var terminal: Terminal?

    var axis: SplitAxis
    var children: [PaneNode]
    /// Each child's fraction of the branch's length along `axis`; sums to ~1.
    var fractions: [Double]

    init(terminal: Terminal) {
        self.terminal = terminal
        self.axis = .horizontal
        self.children = []
        self.fractions = []
    }

    init(axis: SplitAxis, children: [PaneNode], fractions: [Double]? = nil) {
        self.terminal = nil
        self.axis = axis
        self.children = children
        if let fractions, fractions.count == children.count {
            self.fractions = fractions
        } else {
            let n = max(children.count, 1)
            self.fractions = Array(repeating: 1.0 / Double(n), count: children.count)
        }
    }

    var isLeaf: Bool { terminal != nil }

    /// All terminals at the leaves, left-to-right / top-to-bottom.
    var leafTerminals: [Terminal] {
        if let terminal { return [terminal] }
        return children.flatMap { $0.leafTerminals }
    }

    /// The branch directly containing `terminalID`'s leaf and its child index.
    func parent(of terminalID: UUID) -> (branch: PaneNode, index: Int)? {
        for (i, child) in children.enumerated() {
            if child.terminal?.id == terminalID { return (self, i) }
            if let found = child.parent(of: terminalID) { return found }
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
        if terminal?.id == targetID {
            convertLeafToBranch(self, adding: newLeaf, axis: axis)
            return true
        }
        return false
    }

    private func convertLeafToBranch(_ leaf: PaneNode, adding newLeaf: PaneNode, axis: SplitAxis) {
        guard let term = leaf.terminal else { return }
        let moved = PaneNode(terminal: term)
        leaf.terminal = nil
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

        var newChildren: [PaneNode] = []
        var newFractions: [Double] = []
        for (i, child) in children.enumerated() {
            if !child.isLeaf, child.children.count == 1 {
                newChildren.append(child.children[0])
            } else {
                newChildren.append(child)
            }
            newFractions.append(fractions[i])
        }
        children = newChildren
        fractions = newFractions

        // Absorb a lone branch child; a lone leaf child means the tab is unsplit
        // again and the caller dissolves the tree.
        if children.count == 1, let only = children.first, !only.isLeaf {
            axis = only.axis
            fractions = only.fractions
            children = only.children
        }
    }
}
