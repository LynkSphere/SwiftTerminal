import SwiftUI

struct ThreadListRows: View {
    @Environment(AgentIntegrationStore.self) private var integrations
    let threads: [AgentThread]
    let rowPositions: Namespace.ID
    let requestDeletion: (AgentThread) -> Void

    var body: some View {
        ForEach(threads) { thread in
            ThreadRowView(thread: thread)
                .matchedGeometryEffect(id: thread.id, in: rowPositions, properties: .position)
                .tag(thread.id)
                .contextMenu {
                    SettleThreadButton(thread: thread)
                    if integrations.canMarkUnread(thread) {
                        MarkThreadUnreadButton(thread: thread)
                    }
                    if integrations.supportsDeletion(thread) {
                        Divider()
                        DeleteThreadButton(thread: thread) { requestDeletion(thread) }
                    }
                }
                .swipeActions(edge: .leading) {
                    SettleThreadButton(thread: thread)
                        .labelStyle(.iconOnly)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    // Keep the row visible until confirmation; a destructive swipe role
                    // would optimistically animate it away before the alert is answered.
                    DeleteThreadButton(thread: thread, role: nil) { requestDeletion(thread) }
                        .labelStyle(.iconOnly)
                }
        }
    }
}
