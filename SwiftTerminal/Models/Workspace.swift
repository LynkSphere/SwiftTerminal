import Foundation
import SwiftData
import SwiftTerm

@Model
final class Workspace {
    var id = UUID()
    var name: String = ""
    var directory: String?
    var sortOrder: Int = 0
    var selectedTab: TerminalTab?

    @Relationship(deleteRule: .cascade, inverse: \TerminalTab.workspace)
    var tabs: [TerminalTab] = []

    init(name: String, directory: String? = nil, sortOrder: Int = 0) {
        self.name = name
        self.directory = directory
        self.sortOrder = sortOrder
    }

    var sortedTabs: [TerminalTab] {
        tabs.sorted { $0.sortOrder < $1.sortOrder }
    }

    @discardableResult
    func addTab(currentDirectory: String? = nil) -> TerminalTab {
        let ordered = sortedTabs
        let insertIndex: Int
        if let current = selectedTab, let currentIndex = ordered.firstIndex(of: current) {
            insertIndex = currentIndex + 1
        } else {
            insertIndex = ordered.count
        }

        // Shift tabs at or after the insert position
        for t in ordered where t.sortOrder >= insertIndex {
            t.sortOrder += 1
        }

        let tab = TerminalTab(currentDirectory: currentDirectory, sortOrder: insertIndex)
        tabs.append(tab)
        selectedTab = tab
        return tab
    }

    func closeTab(_ tab: TerminalTab) {
        tab.terminate()
        tabs.removeAll { $0.id == tab.id }
        tab.modelContext?.delete(tab)
        if selectedTab?.id == tab.id {
            selectedTab = sortedTabs.last
        }
    }

    func moveTab(_ tab: TerminalTab, before destinationTab: TerminalTab) {
        let ordered = sortedTabs
        guard tab !== destinationTab,
              let sourceIndex = ordered.firstIndex(of: tab),
              let destinationIndex = ordered.firstIndex(of: destinationTab) else {
            return
        }
        moveTab(tab, to: sourceIndex < destinationIndex ? destinationIndex - 1 : destinationIndex)
    }

    func moveTab(_ tab: TerminalTab, to destinationIndex: Int) {
        var ordered = sortedTabs
        guard let sourceIndex = ordered.firstIndex(of: tab) else { return }
        let movingTab = ordered.remove(at: sourceIndex)
        let clamped = max(0, min(destinationIndex, ordered.count))
        ordered.insert(movingTab, at: clamped)
        for (i, t) in ordered.enumerated() {
            t.sortOrder = i
        }
    }

    func selectNextTab() {
        let ordered = sortedTabs
        guard ordered.count > 1,
              let current = selectedTab,
              let index = ordered.firstIndex(of: current) else { return }
        selectTab(ordered[(index + 1) % ordered.count])
    }

    func selectPreviousTab() {
        let ordered = sortedTabs
        guard ordered.count > 1,
              let current = selectedTab,
              let index = ordered.firstIndex(of: current) else { return }
        selectTab(ordered[(index - 1 + ordered.count) % ordered.count])
    }

    func selectTab(_ tab: TerminalTab) {
        selectedTab = tab
        tab.clearNotification()
    }

    var notificationCount: Int {
        tabs.filter { $0.hasBellNotification }.count
    }

    var runningProcessCount: Int {
        let shellPids: [pid_t] = tabs.compactMap { tab in
            guard let tv = tab.localProcessTerminalView else { return nil }
            let pid = tv.process.shellPid
            return pid > 0 ? pid : nil
        }
        guard !shellPids.isEmpty else { return 0 }

        let shellPidSet = Set(shellPids)

        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size: Int = 0
        sysctl(&mib, 3, nil, &size, nil, 0)
        let count = size / MemoryLayout<kinfo_proc>.stride
        let procs = UnsafeMutablePointer<kinfo_proc>.allocate(capacity: count)
        defer { procs.deallocate() }
        sysctl(&mib, 3, procs, &size, nil, 0)
        let actualCount = size / MemoryLayout<kinfo_proc>.stride

        var pidsWithChildren = Set<pid_t>()
        for i in 0..<actualCount {
            let parentPid = procs[i].kp_eproc.e_ppid
            if shellPidSet.contains(parentPid) {
                pidsWithChildren.insert(parentPid)
            }
        }
        return pidsWithChildren.count
    }

    func terminateAll() {
        for tab in tabs {
            tab.terminate()
        }
    }
}
