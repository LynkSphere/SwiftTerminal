import SwiftUI

struct ThreadListView: View {
    @Environment(AgentIntegrationStore.self) private var integrations
    @Environment(TaskSessionController.self) private var sessions
    @Environment(AppState.self) private var appState
    let searchText: String

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
        List(selection: Binding<String?>(get: { appState.selectedSession?.id }, set: { id in
            guard let thread = threads.first(where: { $0.id == id }) else { return }
            Task { await sessions.open(thread) }
        })) {
            ForEach(threads) { thread in
                ThreadRowView(thread: thread)
                    .tag(thread.id)
                    .contextMenu {
                        SettleThreadButton(thread: thread)
                        if thread.provider == .codex && thread.readState != nil {
                            MarkThreadUnreadButton(thread: thread)
                        }
                    }
                    .swipeActions(edge: .leading) {
                        SettleThreadButton(thread: thread)
                            .labelStyle(.iconOnly)
                    }
                    .swipeActions(edge: .trailing) {
                        if thread.provider == .codex && thread.readState != nil {
                            MarkThreadUnreadButton(thread: thread)
                                .labelStyle(.iconOnly)
                        }
                    }
            }
        }
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
        .safeAreaBar(edge: .bottom) {
            HStack {
                Button("Compose", systemImage: "square.and.pencil") { appState.showingCompose = true }
                    .disabled(sessions.isOpening || !integrations.isEnabled)
                Spacer()
            }
            .buttonStyle(.plain)
            .padding(12.5)
        }
        .sheet(isPresented: Bindable(appState).showingCompose) { ComposeThreadView() }
        .alert("Couldn’t Update Thread", isPresented: Binding(
            get: { integrations.actionError != nil && !appState.showingCompose },
            set: { if !$0 { integrations.actionError = nil } }
        )) {
            Button("OK") { integrations.actionError = nil }
        } message: {
            Text(integrations.actionError ?? "")
        }
    }
}
