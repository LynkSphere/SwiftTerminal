import AppKit

/// Split-pane operations on the active tab, mutating the session-only `paneTrees`.
extension AppState {

    // MARK: - Queries

    func isTabSplit(_ tab: Terminal) -> Bool {
        paneTrees[tab.id] != nil
    }

    func paneTerminals(for tab: Terminal) -> [Terminal] {
        paneTrees[tab.id]?.leafTerminals ?? [tab]
    }

    /// Falls back to the tab's first pane (or the tab itself) when `focusedPaneID`
    /// is unset or points at another tab.
    func resolvedFocusedPane(for tab: Terminal) -> Terminal {
        guard let tree = paneTrees[tab.id] else { return tab }
        let leaves = tree.leafTerminals
        if let id = focusedPaneID, let match = leaves.first(where: { $0.id == id }) {
            return match
        }
        return leaves.first ?? tab
    }

    func isPaneActive(_ terminal: Terminal, in tab: Terminal) -> Bool {
        resolvedFocusedPane(for: tab).id == terminal.id
    }

    /// The terminal that pane-scoped actions (clear, etc.) should target.
    var actionTargetPane: Terminal? {
        guard let tab = selectedTerminal else { return nil }
        return resolvedFocusedPane(for: tab)
    }

    // MARK: - Splitting

    func splitActivePane(_ axis: SplitAxis) {
        guard let workspace = selectedWorkspace, let tab = selectedTerminal else { return }
        let focused = resolvedFocusedPane(for: tab)
        let newPane = workspace.makeDetachedPane(currentDirectory: focused.currentDirectory)
        let newLeaf = PaneNode(terminal: newPane)

        if let tree = paneTrees[tab.id] {
            guard tree.split(targetID: focused.id, with: newLeaf, axis: axis) else { return }
        } else {
            paneTrees[tab.id] = PaneNode(
                axis: axis,
                children: [PaneNode(terminal: tab), newLeaf]
            )
        }
        focusedPaneID = newPane.id
    }

    // MARK: - Closing

    /// Removes `pane`, terminating its shell, redistributing space, and migrating
    /// tab identity if it was the tab's representative. Dissolves the tree back to
    /// an unsplit tab when one pane remains.
    func closePane(_ pane: Terminal, in tab: Terminal) {
        guard let workspace = selectedWorkspace, let tree = paneTrees[tab.id] else { return }
        guard let (branch, idx) = tree.parent(of: pane.id) else { return }

        let neighbor = idx + 1 < branch.children.count ? branch.children[idx + 1]
            : (idx - 1 >= 0 ? branch.children[idx - 1] : nil)
        let preferredFocusID = neighbor?.leafTerminals.first?.id
        let wasRepresentative = pane.id == tab.id

        tree.removeLeaf(targetID: pane.id)
        pane.terminate()

        let leaves = tree.leafTerminals
        if leaves.count <= 1 {
            paneTrees[tab.id] = nil
            if let survivor = leaves.first {
                focusedPaneID = survivor.id
                if survivor.id != tab.id {
                    migrateTabIdentity(from: tab, to: survivor, in: workspace)
                }
            }
            return
        }

        if wasRepresentative, let survivor = leaves.first {
            paneTrees[survivor.id] = tree
            paneTrees[tab.id] = nil
            migrateTabIdentity(from: tab, to: survivor, in: workspace)
        }

        if let id = preferredFocusID, leaves.contains(where: { $0.id == id }) {
            focusedPaneID = id
        } else {
            focusedPaneID = leaves.first?.id
        }
    }

    /// Terminates a tab's extra panes and drops its tree before the tab itself is
    /// closed, so split-child shells don't leak.
    func tearDownPanes(for tab: Terminal) {
        guard let tree = paneTrees[tab.id] else { return }
        for terminal in tree.leafTerminals where terminal.id != tab.id {
            terminal.terminate()
        }
        paneTrees[tab.id] = nil
    }

    private func migrateTabIdentity(from old: Terminal, to new: Terminal, in workspace: Workspace) {
        workspace.replaceTerminal(old, with: new)
        if selectedTerminal === old {
            selectedTerminal = new
        }
    }

    // MARK: - Focus movement

    /// Moves pane focus to the spatially nearest pane in `direction`, using the
    /// live terminal views' on-screen frames.
    func movePaneFocus(_ direction: PaneFocusDirection) {
        guard let tab = selectedTerminal, isTabSplit(tab) else { return }
        let current = resolvedFocusedPane(for: tab)
        guard let currentView = current.localProcessTerminalView,
              let window = currentView.window else { return }

        let currentRect = currentView.convert(currentView.bounds, to: nil)
        let origin = CGPoint(x: currentRect.midX, y: currentRect.midY)

        var best: (terminal: Terminal, distance: CGFloat)?
        for terminal in paneTerminals(for: tab) where terminal.id != current.id {
            guard let view = terminal.localProcessTerminalView, view.window === window else { continue }
            let rect = view.convert(view.bounds, to: nil)
            let dx = rect.midX - origin.x
            let dy = rect.midY - origin.y  // window coords are y-up

            let matches: Bool
            switch direction {
            case .left: matches = dx < -1 && abs(dx) >= abs(dy)
            case .right: matches = dx > 1 && abs(dx) >= abs(dy)
            case .up: matches = dy > 1 && abs(dy) >= abs(dx)
            case .down: matches = dy < -1 && abs(dy) >= abs(dx)
            }
            guard matches else { continue }

            let distance = dx * dx + dy * dy
            if best == nil || distance < best!.distance {
                best = (terminal, distance)
            }
        }

        if let best {
            focusedPaneID = best.terminal.id
        }
    }
}
