import Foundation
import Network

@MainActor
final class ClaudeHookServer {
    var onEvent: ((ClaudeHookEvent) -> Void)?
    private let token = UUID().uuidString
    private var listener: NWListener?
    private var startup: Task<UInt16, Error>?
    private var ready: CheckedContinuation<UInt16, Error>?
    private var connections: [UUID: ClaudeHookConnection] = [:]

    func settings() async throws -> String {
        let port = try await start()
        let handler: [String: Any] = [
            "type": "http", "url": "http://127.0.0.1:\(port)/claude",
            "headers": ["Authorization": "Bearer \(token)"], "timeout": 2
        ]
        let events = ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                      "PostToolUseFailure", "PermissionRequest", "Elicitation", "ElicitationResult", "Stop", "StopFailure"]
        var hooks: [String: [[String: Any]]] = Dictionary(uniqueKeysWithValues: events.map { ($0, [["hooks": [handler]]]) })
        hooks["Notification"] = [[
            "matcher": "permission_prompt|elicitation_dialog|elicitation_url_dialog", "hooks": [handler]
        ]]
        return String(decoding: try JSONSerialization.data(withJSONObject: ["hooks": hooks]), as: UTF8.self)
    }

    private func start() async throws -> UInt16 {
        if let startup { return try await startup.value }
        if let port = listener?.port { return port.rawValue }
        let task = Task { try await listen() }
        startup = task
        defer { startup = nil }
        return try await task.value
    }

    private func listen() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        let timeout = Task { [weak self] in
            try await Task.sleep(for: .seconds(5))
            self?.stop()
        }
        defer { timeout.cancel() }
        return try await withCheckedThrowingContinuation { continuation in
            ready = continuation
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self, self.listener === listener else { return }
                    switch state {
                    case .ready:
                        if let port = listener.port {
                            self.ready?.resume(returning: port.rawValue)
                            self.ready = nil
                        }
                    case .failed(let error):
                        self.ready?.resume(throwing: error)
                        self.ready = nil
                        self.stop()
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in
                    guard let self, self.listener === listener, self.connections.count < 32 else {
                        connection.cancel()
                        return
                    }
                    let id = UUID()
                    let request = ClaudeHookConnection(connection: connection, token: self.token) { [weak self] event in
                        self?.onEvent?(event)
                    } onClose: { [weak self] in
                        self?.connections[id] = nil
                    }
                    self.connections[id] = request
                    request.start()
                }
            }
            listener.start(queue: .global(qos: .utility))
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        ready?.resume(throwing: CancellationError())
        ready = nil
        let active = Array(connections.values)
        for connection in active { connection.close() }
    }
}
