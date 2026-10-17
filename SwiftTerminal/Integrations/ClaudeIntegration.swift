import Foundation

enum ClaudeIntegration {
    static func listThreads() async throws -> [AgentThread] {
        guard let helper = Bundle.main.url(forResource: "claude-history", withExtension: "mjs", subdirectory: "Integrations") else {
            throw IntegrationError(message: "The Claude history helper is missing. Rebuild SwiftTerminal.")
        }
        let sdk = try await ClaudeSDK.url()
        let history = try await IntegrationProcess.run("node", arguments: [helper.path, sdk.path])
        return try parseHistory(history)
    }

    static func readThread(_ id: String) async throws -> AgentThread? {
        guard let helper = Bundle.main.url(forResource: "claude-history", withExtension: "mjs", subdirectory: "Integrations") else {
            throw IntegrationError(message: "The Claude history helper is missing.")
        }
        let sdk = try await ClaudeSDK.url()
        return try parseHistory(await IntegrationProcess.run("node", arguments: [helper.path, sdk.path, id])).first
    }

    private static func parseHistory(_ history: Data) throws -> [AgentThread] {
        guard let rows = try JSONSerialization.jsonObject(with: history) as? [[String: Any]] else {
            throw IntegrationError(message: "Claude returned invalid session history.")
        }
        let threads: [AgentThread] = rows.compactMap { row in
            guard let id = row["sessionId"] as? String, let directory = row["cwd"] as? String else { return nil }
            return AgentThread(
                sessionID: id, provider: .claude, title: row["title"] as? String ?? "Claude thread", directory: directory,
                updatedAt: Date(timeIntervalSince1970: (row["lastModified"] as? Double ?? 0) / 1000), status: .unknown,
                hasProviderTitle: row["hasProviderTitle"] as? Bool ?? false
            )
        }
        return Array(AgentThread.unique(threads).prefix(25))
    }
}
