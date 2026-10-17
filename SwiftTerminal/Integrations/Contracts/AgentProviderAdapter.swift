import Foundation

/// Provider boundary. Implementations own connections, SDKs, wire formats, and CLI options.
/// Events and snapshots use only the shared models consumed by AgentIntegrationStore.
@MainActor
protocol AgentProviderAdapter: AnyObject {
    var provider: AgentProvider { get }
    var capabilities: AgentCapabilities { get }
    var activityPolicy: AgentActivityPolicy { get }
    var onEvent: ((AgentEvent) -> Void)? { get set }

    func listThreads() async throws -> [AgentThread]
    func readThread(_ sessionID: String) async throws -> AgentThread?
    func createThread(directory: String) async throws -> AgentThread
    func prepareLaunch(for thread: AgentThread, intent: AgentLaunchIntent) async throws -> AgentLaunch
    func markUnread(_ thread: AgentThread) async throws -> AgentReadState
    func deleteThread(_ thread: AgentThread) async throws
    func title(from reportedTitle: String) -> String?
    func didExit(_ thread: AgentThread)
    func forgetThread(_ sessionID: String)
    /// Suspend background work when hidden, preserving resources needed by retained terminals.
    func setEnabled(_ isEnabled: Bool)
}

extension AgentProviderAdapter {
    var capabilities: AgentCapabilities { [] }
    var activityPolicy: AgentActivityPolicy { .providerTimestamp }

    func markUnread(_ thread: AgentThread) async throws -> AgentReadState {
        throw IntegrationError(message: "\(provider.name) does not support marking a thread unread.")
    }

    func deleteThread(_ thread: AgentThread) async throws {
        throw IntegrationError(message: "\(provider.name) does not support deleting a thread.")
    }

    func title(from reportedTitle: String) -> String? { nil }
    func didExit(_ thread: AgentThread) {}
    func forgetThread(_ sessionID: String) {}
    func setEnabled(_ isEnabled: Bool) {}
}
