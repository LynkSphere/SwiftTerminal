import Foundation
import ACP

extension ACPSession {
    func listenForNotifications(client: Client) {
        notificationTask?.cancel()
        notificationTask = Task {
            let decoder = JSONDecoder()
            let encoder = JSONEncoder()

            for await notification in await client.notifications {
                guard !Task.isCancelled else { break }

                guard notification.method == "session/update",
                      let params = notification.params else { continue }

                do {
                    let data = try encoder.encode(params)
                    let update = try decoder.decode(SessionUpdateNotification.self, from: data)
                    await handleUpdate(update.update)
                } catch {
                    // Skip unparseable notifications
                }
            }
        }
    }

    @MainActor
    private func handleUpdate(_ update: SessionUpdate) {
        // Drop updates streamed back by the agent while replaying a resumed
        // session — our persisted messages are the source of truth.
        if isReplaying { return }
        onSessionUpdate?(update)
    }
}
