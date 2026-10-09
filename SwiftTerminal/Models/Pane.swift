import AppKit
import Observation

@MainActor @Observable
final class Pane: Identifiable, Hashable {
    let id: UUID
    let content: PaneContent
    @ObservationIgnored weak var workspace: Workspace? {
        didSet { terminal?.workspace = workspace }
    }
    @ObservationIgnored weak var focusRegion: NSView?

    init(content: PaneContent, workspace: Workspace) {
        self.content = content
        switch content {
        case .terminal(let terminal):
            self.id = terminal.id
            terminal.workspace = workspace
        }
        self.workspace = workspace
    }

    var terminal: Terminal? {
        guard case .terminal(let terminal) = content else { return nil }
        return terminal
    }

    var displayTitle: String {
        switch content {
        case .terminal(let terminal): terminal.displayTitle
        }
    }

    var paneView: NSView? {
        focusRegion ?? terminal?.localProcessTerminalView
    }

    func close() {
        terminal?.close()
    }

    static func == (lhs: Pane, rhs: Pane) -> Bool { lhs.id == rhs.id }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum PaneContent {
    case terminal(Terminal)
}

enum SplitAxis: String, Codable, CaseIterable, Identifiable {
    case horizontal
    case vertical

    var id: Self { self }
}

enum PaneFocusDirection {
    case left, right, up, down
}
