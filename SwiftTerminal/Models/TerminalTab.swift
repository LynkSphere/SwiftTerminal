import Foundation
import SwiftTerm

@Observable
final class TerminalTab: Identifiable {
    let id: UUID
    var title: String = "Terminal" {
        didSet {
            guard title != oldValue else { return }
            onPersistChange?()
        }
    }
    var currentDirectory: String? {
        didSet {
            guard currentDirectory != oldValue else { return }
            onPersistChange?()
        }
    }
    var hasBellNotification = false
    var workspaceID: UUID?
    var localProcessTerminalView: LocalProcessTerminalView?
    var hasChildProcess: Bool {
        guard let tv = localProcessTerminalView else { return false }
        let shellPid = tv.process.shellPid
        guard shellPid > 0 else { return false }

        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size: Int = 0
        sysctl(&mib, 3, nil, &size, nil, 0)
        let count = size / MemoryLayout<kinfo_proc>.stride
        let procs = UnsafeMutablePointer<kinfo_proc>.allocate(capacity: count)
        defer { procs.deallocate() }
        sysctl(&mib, 3, procs, &size, nil, 0)
        let actualCount = size / MemoryLayout<kinfo_proc>.stride

        for i in 0..<actualCount {
            if procs[i].kp_eproc.e_ppid == shellPid {
                return true
            }
        }
        return false
    }
    var onPersistChange: (() -> Void)?

    init(
        id: UUID = UUID(),
        title: String = "Terminal",
        currentDirectory: String? = nil
    ) {
        self.id = id
        self.title = title
        self.currentDirectory = currentDirectory
    }

    var displayDirectory: String {
        guard let currentDirectory else { return "" }
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        if currentDirectory.hasPrefix(homeDirectory) {
            let relativePath = String(currentDirectory.dropFirst(homeDirectory.count))
            return "~" + relativePath
        }
        return currentDirectory
    }

    func terminate() {
        // LocalProcessTerminalView cleans up its process on dealloc
        localProcessTerminalView = nil
    }

    func increaseFontSize() {
        guard let tv = localProcessTerminalView else { return }
        tv.font = NSFont(descriptor: tv.font.fontDescriptor, size: tv.font.pointSize + 1) ?? tv.font
    }

    func decreaseFontSize() {
        guard let tv = localProcessTerminalView else { return }
        let newSize = max(tv.font.pointSize - 1, 8)
        tv.font = NSFont(descriptor: tv.font.fontDescriptor, size: newSize) ?? tv.font
    }

    func resetFontSize() {
        guard let tv = localProcessTerminalView else { return }
        tv.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    }

    func rename(to name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard title != trimmedName else { return }
        title = trimmedName
    }
}

extension TerminalTab: Hashable {
    static func == (lhs: TerminalTab, rhs: TerminalTab) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
