import Foundation

@MainActor
final class CodexIntegration {
    private let socket = CodexSocket()
    private var connected = false
    private var connectionTask: Task<Void, Error>?
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private(set) var socketPath: String?
    var onReadStateChange: ((String, CodexReadState) -> Void)?
    var onStatusChange: ((String, AgentThreadStatus) -> Void)?
    var onThreadChange: ((String) -> Void)?
    var onListChange: (() -> Void)?
    var onDisconnect: (() -> Void)?

    init() {
        socket.onMessage = { [weak self] in self?.receive($0) }
        socket.onClose = { [weak self] in self?.disconnect(error: $0) }
    }

    func connect() async throws {
        guard !connected else { return }
        if let connectionTask { return try await connectionTask.value }
        let task = Task { try await establishConnection() }
        connectionTask = task
        defer { connectionTask = nil }
        try await task.value
    }

    private func establishConnection() async throws {
        _ = try await IntegrationProcess.run("codex", arguments: ["app-server", "daemon", "start"])
        let version = try await IntegrationProcess.run("codex", arguments: ["app-server", "daemon", "version"])
        guard let info = try JSONSerialization.jsonObject(with: version) as? [String: Any],
              let path = info["socketPath"] as? String else {
            throw IntegrationError(message: "Codex did not provide its app-server socket. Update the Codex CLI and try again.")
        }
        try await socket.connect(path: path)
        socketPath = path
        do {
            _ = try await request("initialize", params: ["clientInfo": ["name": "swiftterminal", "title": "SwiftTerminal", "version": "1.0"], "capabilities": ["experimentalApi": true]])
            socket.send(try JSONSerialization.data(withJSONObject: ["method": "initialized"]))
            connected = true
        } catch {
            disconnect(error: error)
            throw error
        }
    }

    func listThreads() async throws -> [AgentThread] {
        try await connect()
        let data = try await request("thread/list", params: [
            "limit": 25, "sortKey": "recency_at", "sortDirection": "desc",
            "sourceKinds": ["cli", "vscode", "appServer"], "archived": false
        ])
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = result["data"] as? [[String: Any]] else {
            throw IntegrationError(message: "Codex returned an invalid thread list.")
        }
        let readStates = result["readStates"] as? [String: [String: Any]] ?? [:]
        return AgentThread.unique(rows.compactMap { row in
            guard var thread = Self.thread(row) else { return nil }
            thread.readState = CodexReadState(readStates[thread.sessionID])
            return thread
        })
    }

    func readThread(_ id: String) async throws -> AgentThread {
        try await connect()
        let data = try await request("thread/read", params: ["threadId": id, "includeTurns": false])
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let row = result["thread"] as? [String: Any], var thread = Self.thread(row) else {
            throw IntegrationError(message: "Codex returned an invalid thread.")
        }
        thread.readState = CodexReadState(result["readState"] as? [String: Any])
        return thread
    }

    func markUnread(threadID: String, revision: String) async throws -> CodexReadState {
        try await connect()
        let data = try await request("thread/readState/update", params: [
            "threadId": threadID, "expectedRevision": revision, "operation": ["type": "unread"]
        ])
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let state = CodexReadState(result["readState"] as? [String: Any]) else {
            throw IntegrationError(message: "Codex returned an invalid read state.")
        }
        return state
    }

    func startThread(directory: String) async throws -> AgentThread {
        try await connect()
        let data = try await request("thread/start", params: ["cwd": directory])
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let row = result["thread"] as? [String: Any], let thread = Self.thread(row) else {
            throw IntegrationError(message: "Codex did not return a new thread.")
        }
        // Naming persists an empty thread so the terminal UI can resume it.
        _ = try await request("thread/name/set", params: ["threadId": thread.sessionID, "name": "New Codex thread"])
        _ = try await request("thread/unsubscribe", params: ["threadId": thread.sessionID])
        return thread
    }

    func close() {
        connectionTask?.cancel()
        disconnect(error: CancellationError())
    }

    private func request(_ method: String, params: [String: Any]) async throws -> Data {
        nextID += 1
        let id = nextID
        let data = try JSONSerialization.data(withJSONObject: ["id": id, "method": method, "params": params])
        let timeout = Task { [weak self] in
            try await Task.sleep(for: .seconds(15))
            self?.disconnect(error: IntegrationError(message: "Codex request timed out."))
        }
        defer { timeout.cancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
                socket.send(data)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.pending.removeValue(forKey: id)?.resume(throwing: CancellationError())
            }
        }
    }

    private func receive(_ data: Data) {
        guard let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if message["method"] == nil, let id = message["id"] as? Int, let continuation = pending.removeValue(forKey: id) {
            if let error = message["error"] as? [String: Any] {
                continuation.resume(throwing: IntegrationError(message: error["message"] as? String ?? "Codex request failed."))
            } else if let result = message["result"], let data = try? JSONSerialization.data(withJSONObject: result) {
                continuation.resume(returning: data)
            } else {
                continuation.resume(throwing: IntegrationError(message: "Codex returned an invalid response."))
            }
        } else if let method = message["method"] as? String,
                  let params = message["params"] as? [String: Any] {
            if ["thread/started", "thread/archived", "thread/unarchived", "thread/deleted"].contains(method) {
                onListChange?()
                return
            }
            guard let id = params["threadId"] as? String else { return }
            if method == "thread/status/changed" {
                onStatusChange?(id, .codex(params["status"] as? [String: Any]))
                onThreadChange?(id)
            } else if method == "thread/name/updated" {
                onThreadChange?(id)
            } else if method == "thread/readState/changed", let state = CodexReadState(params["readState"] as? [String: Any]) {
                onReadStateChange?(id, state)
            } else if method == "turn/completed" {
                let turn = params["turn"] as? [String: Any]
                switch turn?["status"] as? String {
                case "completed": onStatusChange?(id, .done)
                case "failed": onStatusChange?(id, .failed)
                case "interrupted": onStatusChange?(id, .stopped)
                default: break
                }
                onThreadChange?(id)
            }
        }
    }

    private func disconnect(error: Error) {
        let wasConnected = connected
        connected = false
        socketPath = nil
        socket.close()
        let requests = pending.values
        pending.removeAll()
        for continuation in requests { continuation.resume(throwing: error) }
        if wasConnected { onDisconnect?() }
    }

    static func thread(_ row: [String: Any]) -> AgentThread? {
        guard let id = row["id"] as? String, let directory = row["cwd"] as? String else { return nil }
        let name = (row["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = row["preview"] as? String ?? ""
        let hasProviderTitle = !name.isEmpty && name != "New Codex thread"
        return AgentThread(
            sessionID: id, provider: .codex,
            title: hasProviderTitle ? name : (preview.isEmpty ? "New Codex thread" : String(preview.prefix(160))),
            directory: directory, updatedAt: Date(timeIntervalSince1970: row["recencyAt"] as? Double ?? row["updatedAt"] as? Double ?? 0),
            status: .codex(row["status"] as? [String: Any]), hasProviderTitle: hasProviderTitle
        )
    }
}
