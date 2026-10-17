import Foundation
import Network

@MainActor
final class ClaudeHookConnection {
    private let connection: NWConnection
    private let token: String
    private let onEvent: (ClaudeHookEvent) -> Void
    private let onClose: () -> Void
    private var buffer = Data()
    private var timeout: Task<Void, Error>?
    private var closed = false

    init(connection: NWConnection, token: String, onEvent: @escaping (ClaudeHookEvent) -> Void, onClose: @escaping () -> Void) {
        self.connection = connection
        self.token = token
        self.onEvent = onEvent
        self.onClose = onClose
    }

    func start() {
        timeout = Task { [weak self] in
            try await Task.sleep(for: .seconds(5))
            self?.close()
        }
        connection.start(queue: .global(qos: .utility))
        receive()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            Task { @MainActor [weak self] in
                guard let self, !self.closed else { return }
                if let data { self.buffer.append(data) }
                if self.consume() { return }
                if complete || error != nil { self.close() }
                else { self.receive() }
            }
        }
    }

    private func consume() -> Bool {
        guard buffer.count <= 1_048_576 else { respond("413 Payload Too Large"); return true }
        guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            if buffer.count > 16_384 { respond("431 Request Header Fields Too Large"); return true }
            return false
        }
        let lines = String(decoding: buffer[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { respond("400 Bad Request"); return true }
            let key = parts[0].lowercased()
            guard headers[key] == nil else { respond("400 Bad Request"); return true }
            headers[key] = parts[1].trimmingCharacters(in: .whitespaces)
        }
        guard lines.first == "POST /claude HTTP/1.1", headers["authorization"] == "Bearer \(token)" else {
            respond("403 Forbidden")
            return true
        }
        guard headers["transfer-encoding"] == nil, let size = headers["content-length"].flatMap(Int.init),
              size >= 0, size <= 1_048_576 - end.upperBound else { respond("400 Bad Request"); return true }
        guard buffer.count >= end.upperBound + size else { return false }
        let body = buffer.subdata(in: end.upperBound..<(end.upperBound + size))
        guard let event = try? JSONDecoder().decode(ClaudeHookEvent.self, from: body) else {
            respond("400 Bad Request")
            return true
        }
        onEvent(event)
        respond("200 OK")
        return true
    }

    private func respond(_ status: String) {
        let response = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { [weak self] _ in
            Task { @MainActor [weak self] in self?.close() }
        })
    }

    func close() {
        guard !closed else { return }
        closed = true
        timeout?.cancel()
        connection.cancel()
        onClose()
    }
}
