import Foundation

@MainActor
enum ClaudeSDK {
    // Share installation between history refreshes and metadata requests.
    private static var preparation: Task<URL, Error>?

    static func url() async throws -> URL {
        if let preparation { return try await preparation.value }
        let task = Task {
            guard let helper = Bundle.main.url(forResource: "claude-history", withExtension: "mjs", subdirectory: "Integrations") else {
                throw IntegrationError(message: "The Claude history helper is missing. Rebuild SwiftTerminal.")
            }
            let directory = URL.applicationSupportDirectory.appending(path: "SwiftTerminal/Integrations/Claude")
            let data = try await IntegrationProcess.run(
                "node", arguments: [helper.path, "--prepare", directory.path], timeout: .seconds(120)
            )
            let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard path.hasPrefix("/"), FileManager.default.fileExists(atPath: path) else {
                throw IntegrationError(message: "Could not prepare the Claude Agent SDK. Try refreshing the integration.")
            }
            return URL(fileURLWithPath: path)
        }
        preparation = task
        do {
            return try await task.value
        } catch {
            preparation = nil
            throw error
        }
    }
}
