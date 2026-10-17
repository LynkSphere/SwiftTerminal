import AppKit
import UserNotifications

extension Notification.Name {
    static let navigateToSession = Notification.Name("navigateToSession")
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppDelegate.clearBadge()
    }

    // Show notifications even when the app is in the foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // Handle notification click — navigate to the workspace/terminal that triggered it
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let workspaceID = userInfo["workspaceID"] as? String,
           let terminalID = userInfo["terminalID"] as? String {
            NotificationCenter.default.post(
                name: .navigateToSession,
                object: nil,
                userInfo: [
                    "workspaceID": workspaceID,
                    "terminalID": terminalID,
                ]
            )
        }
        AppDelegate.clearBadge()
        completionHandler()
    }

    static func sendNotification(workspaceID: UUID, terminalID: UUID, workspaceName: String? = nil, terminalName: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = workspaceName ?? "Terminal"
        content.body = terminalName ?? "Terminal needs attention"
        content.sound = .default
        content.userInfo = [
            "terminalID": terminalID.uuidString,
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

    static func showBadge() {
        NSApplication.shared.dockTile.badgeLabel = " "
    }

    static func clearBadge() {
        NSApplication.shared.dockTile.badgeLabel = nil
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        #if DEBUG
        return .terminateNow
        #else
        let alert = NSAlert()
        alert.messageText = "Quit SwiftTerminal?"
        alert.informativeText = "Are you sure you want to quit?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        return response == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
        #endif
    }
}
