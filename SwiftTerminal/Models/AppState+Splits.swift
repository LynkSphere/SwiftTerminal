import AppKit

extension AppState {
    func splitActivePane(_ axis: SplitAxis) {
        guard let tab = selectedTab, let workspace = tab.workspace else { return }
        let pane = workspace.makeTerminalPane(currentDirectory: tab.focusedPane.terminal?.currentDirectory)
        if tab.split(pane, beside: tab.focusedPane, axis: axis) {
            workspace.store?.scheduleSave()
        }
    }

    @discardableResult
    func moveTab(_ source: WorkspaceTab, into destination: WorkspaceTab, axis: SplitAxis) -> Bool {
        guard source !== destination, let workspace = source.workspace,
              destination.workspace === workspace,
              workspace.tabs.contains(where: { $0 === destination }),
              workspace.removeTab(source) else { return false }
        destination.merge(source, axis: axis)
        selectedWorkspace = workspace
        selectedTab = destination
        return true
    }

    @discardableResult
    func detachPaneToTab(_ pane: Pane, from tab: WorkspaceTab) -> Bool {
        guard let workspace = tab.workspace,
              workspace.tabs.contains(where: { $0 === tab }),
              tab.removePane(pane) else { return false }
        selectedWorkspace = workspace
        selectedTab = workspace.addTab(pane: pane, after: tab)
        return true
    }

    func closePane(_ pane: Pane, in tab: WorkspaceTab) {
        guard let workspace = tab.workspace,
              workspace.tabs.contains(where: { $0 === tab }),
              tab.panes.contains(where: { $0 === pane }) else { return }
        if !tab.isSplit {
            closeTab(tab)
        } else if tab.removePane(pane) {
            pane.close()
            workspace.store?.scheduleSave()
        }
    }

    // MARK: - Focus movement

    /// Moves pane focus to the spatially nearest pane in `direction`, using the
    /// live pane views' on-screen frames.
    func movePaneFocus(_ direction: PaneFocusDirection) {
        guard let tab = selectedTab, tab.isSplit else { return }
        let current = tab.focusedPane
        guard let currentView = current.paneView,
              let window = currentView.window else { return }

        let currentRect = currentView.convert(currentView.bounds, to: nil)
        let origin = CGPoint(x: currentRect.midX, y: currentRect.midY)

        var best: (pane: Pane, distance: CGFloat)?
        for pane in tab.panes where pane.id != current.id {
            guard let view = pane.paneView, view.window === window else { continue }
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
            if distance < (best?.distance ?? .infinity) {
                best = (pane, distance)
            }
        }

        if let best {
            tab.focus(best.pane)
        }
    }
}
