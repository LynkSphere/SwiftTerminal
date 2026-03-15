import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Set by SwiftTerminalApp so the delegate can navigate on notification tap.
    var navigateToTab: ((UUID, UUID) -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppDelegate.updateBadge(count: 0)
    }

    // Show notifications even when the app is in the foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // Handle notification tap → navigate to the originating tab
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let tabIDString = userInfo["tabID"] as? String,
           let workspaceIDString = userInfo["workspaceID"] as? String,
           let tabID = UUID(uuidString: tabIDString),
           let workspaceID = UUID(uuidString: workspaceIDString) {
            navigateToTab?(workspaceID, tabID)
        }
        completionHandler()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let alert = NSAlert()
        alert.messageText = "Quit SwiftTerminal?"
        alert.informativeText = "Are you sure you want to quit?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        return response == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    // MARK: - Helpers

    static func sendNotification(workspaceID: UUID, tabID: UUID) {
        let content = UNMutableNotificationContent()
        content.title = "Terminal"
        content.body = "Terminal needs attention"
        content.sound = .default
        content.userInfo = [
            "tabID": tabID.uuidString,
            "workspaceID": workspaceID.uuidString,
        ]

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    static func bounceDockIcon() {
        NSApplication.shared.requestUserAttention(.criticalRequest)
    }

    static func updateBadge(count: Int) {
        if count > 0 {
            NSApplication.shared.dockTile.badgeLabel = "\(count)"
        } else {
            NSApplication.shared.dockTile.badgeLabel = nil
        }
    }
}
