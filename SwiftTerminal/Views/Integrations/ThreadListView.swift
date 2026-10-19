import SwiftUI

struct ThreadListView: View {
    @Environment(AgentIntegrationStore.self) private var integrations
    @Environment(TaskSessionController.self) private var sessions
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let searchText: String
    @State private var threadToDelete: AgentThread?
    @State private var showingDeleteConfirmation = false
    @SceneStorage("threadList.todayExpanded") private var isTodayExpanded = true
    @SceneStorage("threadList.yesterdayExpanded") private var isYesterdayExpanded = true
    @SceneStorage("threadList.earlierExpanded") private var isEarlierExpanded = true
    @Namespace private var rowPositions

    private var threads: [AgentThread] {
        integrations.visibleThreads.filter {
            searchText.isEmpty || $0.title.localizedStandardContains(searchText) || $0.directory.localizedStandardContains(searchText)
        }
    }

    private var unavailableProviderNames: String {
        integrations.enabledProviders
            .filter { integrations.errors[$0] != nil }
            .map(\.name)
            .formatted(.list(type: .and))
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let groups = ThreadListGroup.groups(
                threads: threads,
                settledThreadIDs: integrations.settledThreadIDs,
                selectedThreadID: appState.selectedSession?.id,
                prioritySelectionID: integrations.prioritySelectionID,
                now: context.date
            )
            List(selection: Binding<String?>(get: { appState.selectedSession?.id }, set: { id in
                guard let thread = threads.first(where: { $0.id == id }) else { return }
                Task { await sessions.open(thread) }
            })) {
                ForEach(groups) { group in
                    if group.section == .priority {
                        Section(group.section.rawValue) {
                            ThreadListRows(threads: group.threads, rowPositions: rowPositions, requestDeletion: requestDeletion)
                        }
                    } else {
                        Section(group.section.rawValue, isExpanded: expansion(for: group.section)) {
                            ThreadListRows(threads: group.threads, rowPositions: rowPositions, requestDeletion: requestDeletion)
                        }
                    }
                }
            }
            .animation(reduceMotion ? nil : .smooth, value: groups.map { [$0.section.rawValue] + $0.threads.map(\.id) })
            .animation(reduceMotion ? nil : .smooth, value: [isTodayExpanded, isYesterdayExpanded, isEarlierExpanded])
            .listStyle(.sidebar)
            .environment(\.sidebarRowSize, .medium) //
            .overlay {
                if !unavailableProviderNames.isEmpty {
                    ContentUnavailableView {
                        Label("\(unavailableProviderNames) unavailable", systemImage: "exclamationmark.circle")
                    } description: {
                        Text("Try again to load tasks.")
                    } actions: {
                        Button("Retry") { Task { await integrations.refresh() } }
                            .disabled(integrations.isRefreshing)
                    }
                } else if threads.isEmpty {
                    if !integrations.isEnabled {
                        ContentUnavailableView {
                            Label("Enable an Integration", systemImage: "puzzlepiece.extension")
                        } description: {
                            Text("Enable Codex or Claude in Settings to open tasks.")
                        } actions: {
                            SettingsLink { Text("Open Settings") }
                        }
                    } else if integrations.isRefreshing {
                        ProgressView("Loading threads…")
                    } else {
                        ContentUnavailableView(searchText.isEmpty ? "No Tasks" : "No Results", systemImage: "bubble.left.and.bubble.right", description: Text("Use Compose to start a task."))
                    }
                }
            }
        }
        .safeAreaBar(edge: .bottom) {
            HStack {
                Button("New Chat", systemImage: "square.and.pencil") { appState.showingCompose = true }
                    .disabled(sessions.isOpening || !integrations.isEnabled)
                Spacer()
            }
            .buttonStyle(.plain)
            .padding(13)
        }
        .sheet(isPresented: Bindable(appState).showingCompose) { ComposeThreadView() }
        .alert("Delete Thread?", isPresented: $showingDeleteConfirmation, presenting: threadToDelete) { thread in
            Button("Delete", role: .destructive) {
                Task { await sessions.delete(thread) }
                threadToDelete = nil
            }
            Button("Cancel", role: .cancel) { threadToDelete = nil }
        }
        .alert("Couldn’t Update Thread", isPresented: Binding(
            get: { integrations.actionError != nil && !appState.showingCompose },
            set: { if !$0 { integrations.actionError = nil } }
        )) {
            Button("OK") { integrations.actionError = nil }
        } message: {
            Text(integrations.actionError ?? "")
        }
    }

    private func expansion(for section: ThreadListSection) -> Binding<Bool> {
        switch section {
        case .priority: .constant(true)
        case .today: $isTodayExpanded
        case .yesterday: $isYesterdayExpanded
        case .earlier: $isEarlierExpanded
        }
    }

    private func requestDeletion(_ thread: AgentThread) {
        guard !sessions.isOpening, integrations.canDelete(thread) else { return }
        threadToDelete = thread
        showingDeleteConfirmation = true
    }
}
