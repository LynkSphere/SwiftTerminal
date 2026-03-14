import Foundation

struct TerminalTabSnapshot: Codable {
    let id: UUID
    let title: String
    let currentDirectory: String?
}

struct WorkspaceSnapshot: Codable {
    let id: UUID
    let name: String
    let tabs: [TerminalTabSnapshot]
    let selectedTabID: UUID?
}

struct AppStateSnapshot: Codable {
    let workspaces: [WorkspaceSnapshot]
    let selectedWorkspaceID: UUID?
}

struct AppStateStore {
    static let `default` = AppStateStore()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let fileManager = FileManager.default

    func load() -> AppStateSnapshot? {
        guard let url = storageURL(),
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? decoder.decode(AppStateSnapshot.self, from: data)
    }

    func save(_ snapshot: AppStateSnapshot) {
        guard let url = storageURL(),
              let data = try? encoder.encode(snapshot) else {
            return
        }

        do {
            let directory = url.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            assertionFailure("Failed to save app state: \(error)")
        }
    }

    private func storageURL() -> URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("SwiftTerminal", isDirectory: true)
            .appendingPathComponent("app-state.json")
    }
}
