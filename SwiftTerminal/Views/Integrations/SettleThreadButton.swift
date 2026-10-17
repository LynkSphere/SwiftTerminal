import SwiftUI

struct SettleThreadButton: View {
    @Environment(TaskSessionController.self) private var sessions
    let thread: AgentThread

    var body: some View {
        Button("Settle Thread", systemImage: "checkmark") {
            sessions.settle(thread)
        }
        .tint(.green)
    }
}
