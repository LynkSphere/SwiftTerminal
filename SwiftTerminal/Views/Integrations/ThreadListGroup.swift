import Foundation

struct ThreadListGroup: Identifiable, Equatable {
    let section: ThreadListSection
    let threads: [AgentThread]

    var id: ThreadListSection { section }

    static func groups(
        threads: [AgentThread],
        settledThreadIDs: Set<String>,
        selectedThreadID: String?,
        prioritySelectionID: String?,
        now: Date,
        calendar: Calendar = .current
    ) -> [Self] {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let grouped = Dictionary(grouping: threads) { thread -> ThreadListSection in
            if !settledThreadIDs.contains(thread.id),
               thread.needsAttention || (thread.id == selectedThreadID && thread.id == prioritySelectionID) {
                return .priority
            }
            if thread.updatedAt >= today { return .today }
            if thread.updatedAt >= yesterday { return .yesterday }
            return .earlier
        }
        return ThreadListSection.allCases.compactMap { section in
            guard let candidates = grouped[section], !candidates.isEmpty else { return nil }
            return Self(section: section, threads: candidates.sorted(by: AgentThread.newestFirst))
        }
    }
}
