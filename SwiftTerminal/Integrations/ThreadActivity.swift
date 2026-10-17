import Foundation

struct ThreadActivity: Codable {
    var date: Date
    private var sourceDate: Date
    private var status: AgentThreadStatus
    private var unread = false
    private var readRevision: String?

    init(thread: AgentThread) {
        date = thread.updatedAt
        sourceDate = thread.updatedAt
        status = thread.status
    }

    mutating func update(_ source: AgentThread, isViewed: Bool, now: Date = .now) -> AgentThread {
        var thread = source
        if thread.status == .idle, [.processing, .done].contains(status) {
            thread.status = .done
        }
        let completed = thread.status == .done && status != .done
        let beganWorking = thread.status == .processing && status != .processing
        let needsInput = thread.status == .waiting && status != .waiting
        if thread.provider == .codex {
            date = source.updatedAt
        } else if beganWorking || completed || needsInput {
            date = max(date, now)
        } else if thread.status == .processing && source.updatedAt > sourceDate {
            date = max(date, source.updatedAt)
        }
        if completed { unread = true }
        if beganWorking { unread = false }
        if thread.status != .unknown { status = thread.status }
        sourceDate = source.updatedAt
        thread.updatedAt = date
        if isViewed { markRead(thread) }
        thread.hasUnreadResult = thread.readState.map { $0.isUnread && $0.revision != readRevision } ?? unread
        return thread
    }

    mutating func markRead(_ thread: AgentThread) {
        unread = false
        readRevision = thread.readState?.revision
    }

    mutating func clearReadRevision() {
        readRevision = nil
    }
}
