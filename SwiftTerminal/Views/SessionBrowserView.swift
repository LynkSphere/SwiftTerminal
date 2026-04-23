import SwiftUI
import ACP

struct SessionBrowserView: View {
    struct DiscoveredSession: Identifiable {
        let provider: AgentProvider
        let info: SessionInfo
        var id: String { "\(provider.rawValue):\(info.sessionId.value)" }
    }

    let workspace: Workspace
    var onSelect: (() -> Void)?

    @Environment(AppState.self) private var appState

    @State private var discovered: [DiscoveredSession] = []
    @State private var isDiscovering = false
    @State private var showACPSessions = false
    @State private var providerErrors: [AgentProvider: String] = [:]
    @State private var loadingId: String?

    var body: some View {
        List {
            // Our stored sessions
            if !workspace.chats.isEmpty {
                Section("Sessions") {
                    ForEach(workspace.chats) { chat in
                        storedSessionRow(chat)
                    }
                }
            }

            // Load existing sessions from agents
            if showACPSessions || !workspace.chats.isEmpty {
                Section {
                    loadSessionsSectionContent
                } header: {
                    if showACPSessions {
                        Text("Existing Sessions")
                    }
                }
            }
        }
        .overlay {
            if workspace.chats.isEmpty && !showACPSessions {
                ContentUnavailableView {
                    Label("No Sessions", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Start a new chat or load existing agent sessions.")
                } actions: {
                    HStack {
                        newChatButton
                        Button("Load Existing Sessions") {
                            showACPSessions = true
                            Task { await discoverSessions() }
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                newChatButton
            }
        }
    }

    @ViewBuilder
    private var loadSessionsSectionContent: some View {
        if showACPSessions {
            if isDiscovering && discovered.isEmpty {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Discovering sessions...")
                        .foregroundStyle(.secondary)
                }
            } else if filteredSessions.isEmpty && providerErrors.isEmpty {
                Text("No additional sessions found.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredSessions) { session in
                    acpSessionRow(session)
                }
                ForEach(Array(providerErrors.keys), id: \.self) { provider in
                    if let message = providerErrors[provider] {
                        Label("\(provider.rawValue): \(message)", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            Button {
                showACPSessions = true
                Task { await discoverSessions() }
            } label: {
                Label("Load Existing Sessions...", systemImage: "arrow.down.circle")
            }
        }
    }

    /// Sessions not already tracked in our data layer, sorted newest-first.
    private var filteredSessions: [DiscoveredSession] {
        let trackedIds = Set(workspace.chats.compactMap(\.acpSessionId))
        return discovered
            .filter { !trackedIds.contains($0.info.sessionId.value) }
            .sorted { ($0.info.updatedAt ?? "") > ($1.info.updatedAt ?? "") }
    }

    private var newChatButton: some View {
        Menu {
            ForEach(AgentProvider.allCases, id: \.self) { provider in
                Button {
                    let chat = workspace.addSession(provider: provider)
                    appState.selectedSession = chat
                    onSelect?()
                } label: {
                    Label(provider.rawValue, image: provider.imageName)
                }
            }
        } label: {
            Label("New Chat", systemImage: "plus")
        } primaryAction: {
            let chat = workspace.addSession(provider: .claude)
            appState.selectedSession = chat
            onSelect?()
        }
    }

    private func storedSessionRow(_ chat: Chat) -> some View {
        Button {
            appState.selectedSession = chat
            onSelect?()
        } label: {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(chat.title)
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            if chat.turnCount > 0 {
                                Text("\(chat.turnCount) turns")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            Text(chat.date, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.quaternary)
                        }
                    }
                } icon: {
                    Image(chat.provider.imageName)
                        .foregroundStyle(
                            chat.isActive ? chat.provider.color : .secondary
                        )
                }

                Spacer()

                if chat.isActive {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if chat.isActive {
                Button {
                    chat.disconnect()
                } label: {
                    Label("Disconnect", systemImage: "bolt.slash")
                }
            }

            Button(role: .destructive) {
                if appState.selectedSession?.id == chat.id {
                    appState.selectedSession = nil
                }
                workspace.removeSession(chat)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func acpSessionRow(_ session: DiscoveredSession) -> some View {
        let isLoading = loadingId == session.id
        let info = session.info

        return HStack {
            Image(session.provider.imageName)
                .foregroundStyle(session.provider.color)

            VStack(alignment: .leading, spacing: 3) {
                Text(info.title ?? info.sessionId.value.prefix(12) + "...")
                    .lineLimit(1)

                if let relative = relativeTime(from: info.updatedAt) {
                    Text(relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Button {
                Task { await importSession(session) }
            } label: {
                ZStack {
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Import")
                    }
                }
                .frame(width: 60)
            }
            .disabled(loadingId != nil)
        }
    }

    private func relativeTime(from updatedAt: String?) -> String? {
        guard let updatedAt, let date = Self.parseDate(updatedAt) else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 2
        formatter.zeroFormattingBehavior = .dropAll
        let interval = max(0, Date().timeIntervalSince(date))
        if interval < 60 { return "just now" }
        guard let str = formatter.string(from: interval) else { return nil }
        return "\(str) ago"
    }

    private static func parseDate(_ string: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: string) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }

    private func discoverSessions() async {
        isDiscovering = true
        providerErrors = [:]
        discovered = []

        await withTaskGroup(of: (AgentProvider, Result<[SessionInfo], Error>).self) { group in
            for provider in AgentProvider.allCases {
                group.addTask {
                    let tempSession = ACPSession()
                    tempSession.provider = provider
                    do {
                        let sessions = try await tempSession.listExistingSessions(
                            workingDirectory: workspace.directory
                        )
                        return (provider, .success(sessions))
                    } catch {
                        return (provider, .failure(error))
                    }
                }
            }

            for await (provider, result) in group {
                switch result {
                case .success(let sessions):
                    discovered.append(contentsOf: sessions.map {
                        DiscoveredSession(provider: provider, info: $0)
                    })
                case .failure(let error):
                    providerErrors[provider] = error.localizedDescription
                }
            }
        }

        isDiscovering = false
    }

    private func importSession(_ session: DiscoveredSession) async {
        loadingId = session.id
        do {
            let chat = try await Chat.loadSession(
                sessionInfo: session.info,
                provider: session.provider,
                workspace: workspace
            )
            workspace.appendChat(chat)
            appState.selectedSession = chat
            onSelect?()
        } catch {
            providerErrors[session.provider] = "Import failed: \(error.localizedDescription)"
        }
        loadingId = nil
    }
}
