// The cat sat on the keyboard.
import Foundation

struct SidebarItem: Identifiable, Hashable {
    let id: String
    let workspace: Workspace?
    let chat: Chat?
    let children: [SidebarItem]?

    static func forWorkspace(_ workspace: Workspace) -> SidebarItem {
        let sessionChildren = workspace.chats
            .filter { !$0.isArchived }
            .map { forSession($0) }
        return SidebarItem(
            id: "w:\(workspace.id.uuidString)",
            workspace: workspace,
            chat: nil,
            children: sessionChildren.isEmpty ? nil : sessionChildren
        )
    }

    static func forSession(_ session: Chat) -> SidebarItem {
        SidebarItem(
            id: "s:\(session.id.uuidString)",
            workspace: nil,
            chat: session,
            children: nil
        )
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: SidebarItem, rhs: SidebarItem) -> Bool {
        lhs.id == rhs.id
    }
}
