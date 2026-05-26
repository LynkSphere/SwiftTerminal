import AppKit
import UserNotifications

extension Notification.Name {
    static let navigateToSession = Notification.Name("navigateToSession")
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private static let mainWindowIdentifier = "swiftterminal"
    private var savedCloseMenuItem: NSMenuItem?
    private var savedCloseMenuIndex: Int?
    private var mainWindowIsKey = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(windowDidBecomeKey(_:)),
                       name: NSWindow.didBecomeKeyNotification, object: nil)
        nc.addObserver(self, selector: #selector(windowDidResignKey(_:)),
                       name: NSWindow.didResignKeyNotification, object: nil)
        nc.addObserver(self, selector: #selector(menuDidChange(_:)),
                       name: NSMenu.didAddItemNotification, object: nil)
    }

    private func isMainAppWindow(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        if let id = window.identifier?.rawValue,
           id == Self.mainWindowIdentifier || id.contains(Self.mainWindowIdentifier) {
            return true
        }
        return window.title == "SwiftTerminal"
    }

    @objc private func windowDidBecomeKey(_ note: Notification) {
        guard let window = note.object as? NSWindow else { return }
        if isMainAppWindow(window) {
            mainWindowIsKey = true
            removeCloseMenuItem()
        }
    }

    @objc private func windowDidResignKey(_ note: Notification) {
        guard let window = note.object as? NSWindow else { return }
        if isMainAppWindow(window) {
            mainWindowIsKey = false
            restoreCloseMenuItem()
        }
    }

    @objc private func menuDidChange(_ notification: Notification) {
        // SwiftUI rebuilds menus from time to time. If the main window is key,
        // strip File > Close again whenever it reappears.
        if mainWindowIsKey {
            removeCloseMenuItem()
        }
    }

    private func fileMenu() -> NSMenu? {
        NSApplication.shared.mainMenu?.items
            .first(where: { $0.submenu?.title == "File" })?.submenu
    }

    private func isSystemCloseItem(_ item: NSMenuItem) -> Bool {
        item.keyEquivalent == "w"
            && item.keyEquivalentModifierMask == .command
            && item.title.localizedCaseInsensitiveContains("close")
            && !item.title.localizedCaseInsensitiveContains("tab")
    }

    private func removeCloseMenuItem() {
        guard let fileMenu = fileMenu() else { return }
        for (index, item) in fileMenu.items.enumerated() where isSystemCloseItem(item) {
            if savedCloseMenuItem == nil {
                savedCloseMenuItem = item
                savedCloseMenuIndex = index
            }
            fileMenu.removeItem(item)
            break
        }
    }

    private func restoreCloseMenuItem() {
        guard let fileMenu = fileMenu(), let item = savedCloseMenuItem else { return }
        if !fileMenu.items.contains(where: isSystemCloseItem) {
            let idx = min(savedCloseMenuIndex ?? fileMenu.items.count, fileMenu.items.count)
            fileMenu.insertItem(item, at: idx)
        }
        savedCloseMenuItem = nil
        savedCloseMenuIndex = nil
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
