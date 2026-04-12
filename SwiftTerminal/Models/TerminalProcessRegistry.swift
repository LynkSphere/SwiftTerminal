import Foundation
import SwiftTerm

/// Owns the live `LocalProcessTerminalView` for each terminal tab.
///
/// Keying the views off `Terminal.id` in a static registry decouples shell
/// process lifetime from the lifetime of any individual `Terminal` instance,
/// mirroring the pattern `CommandRunner` already uses for command execution
/// state.
enum TerminalProcessRegistry {
    private static var views: [UUID: LocalProcessTerminalView] = [:]

    static func view(for id: UUID) -> LocalProcessTerminalView? {
        views[id]
    }

    static func register(_ view: LocalProcessTerminalView, for id: UUID) {
        views[id] = view
    }

    static func remove(for id: UUID) {
        views.removeValue(forKey: id)
    }
}
