import AppKit
import UserNotifications

extension Notification.Name {
    static let navigateToSession = Notification.Name("navigateToSession")
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }

        // Remove the system "Close" (Cmd+W) from File menu so our custom Close Tab command takes priority.
        // SwiftUI can rebuild the menu after launch, so observe changes and re-strip it.
//        removeCloseMenuItem()
//        NotificationCenter.default.addObserver(
//            self,
//            selector: #selector(menuDidChange),
//            name: NSMenu.didAddItemNotification,
//            object: nil
//        )
    }

    @objc private func menuDidChange(_ notification: Notification) {
        removeCloseMenuItem()
    }

    /// Removes the default File > Close menu item so that our Cmd+W shortcut always maps to Close Tab.
    private func removeCloseMenuItem() {
        guard let mainMenu = NSApplication.shared.mainMenu,
              let fileMenu = mainMenu.items.first(where: { $0.submenu?.title == "File" })?.submenu else { return }
        for item in fileMenu.items where item.keyEquivalent == "w" && item.keyEquivalentModifierMask == .command
            && item.title.localizedCaseInsensitiveContains("close") && !item.title.localizedCaseInsensitiveContains("tab") {
            fileMenu.removeItem(item)
            break
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        NSApplication.shared.dockTile.badgeLabel = nil
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
        NSApplication.shared.dockTile.badgeLabel = nil
        completionHandler()
    }

    static func sendNotification(workspaceID: UUID, terminalID: UUID) {
        let content = UNMutableNotificationContent()
        content.title = "Terminal"
        content.body = "Terminal needs attention"
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

    static func updateBadge(count: Int) {
        if count > 0 {
            NSApplication.shared.dockTile.badgeLabel = "\(count)"
        } else {
            NSApplication.shared.dockTile.badgeLabel = nil
        }
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
