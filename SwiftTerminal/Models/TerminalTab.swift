import AppKit
import SwiftData
import SwiftTerm

@Model
final class TerminalTab {
    var id = UUID()
    var title: String = "Terminal"
    var currentDirectory: String?
    var sortOrder: Int = 0
    var workspace: Workspace?

    @Transient var hasBellNotification = false
    @Transient var localProcessTerminalView: LocalProcessTerminalView?

    init(title: String = "Terminal", currentDirectory: String? = nil, sortOrder: Int = 0) {
        self.title = title
        self.currentDirectory = currentDirectory
        self.sortOrder = sortOrder
    }

    var displayDirectory: String {
        guard let currentDirectory else { return "" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return currentDirectory.hasPrefix(home)
            ? "~" + currentDirectory.dropFirst(home.count)
            : currentDirectory
    }

    var liveCurrentDirectory: String? {
        guard let tv = localProcessTerminalView else { return currentDirectory }
        let pid = tv.process.shellPid
        guard pid > 0 else { return currentDirectory }

        var pathInfo = proc_vnodepathinfo()
        let size = MemoryLayout<proc_vnodepathinfo>.size
        let result = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &pathInfo, Int32(size))
        guard result == size else { return currentDirectory }

        let path = withUnsafePointer(to: pathInfo.pvi_cdir.vip_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                String(cString: $0)
            }
        }
        return path.isEmpty ? currentDirectory : path
    }

    var hasChildProcess: Bool {
        !childProcesses().isEmpty
    }

    var foregroundProcessName: String? {
        childProcesses().first?.name
    }

    func terminate() {
        if let tv = localProcessTerminalView {
            let shellPid = tv.process.shellPid
            if shellPid > 0 {
                for child in childProcesses() {
                    kill(child.pid, SIGHUP)
                }
            }
            tv.process.terminate()
        }
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

    private func childProcesses() -> [(pid: pid_t, name: String)] {
        guard let tv = localProcessTerminalView else { return [] }
        let shellPid = tv.process.shellPid
        guard shellPid > 0 else { return [] }

        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size: Int = 0
        sysctl(&mib, 3, nil, &size, nil, 0)
        let count = size / MemoryLayout<kinfo_proc>.stride
        let procs = UnsafeMutablePointer<kinfo_proc>.allocate(capacity: count)
        defer { procs.deallocate() }
        sysctl(&mib, 3, procs, &size, nil, 0)
        let actualCount = size / MemoryLayout<kinfo_proc>.stride

        var children: [(pid: pid_t, name: String)] = []
        for i in 0..<actualCount {
            if procs[i].kp_eproc.e_ppid == shellPid {
                let name = withUnsafePointer(to: procs[i].kp_proc.p_comm) { ptr in
                    ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN) + 1) {
                        String(cString: $0)
                    }
                }
                children.append((procs[i].kp_proc.p_pid, name))
            }
        }
        return children
    }
}
