import Foundation

/// Manages the Node.js bridge process that wraps the Claude Agent SDK.
/// Provides a persistent connection for multi-turn sessions with
/// rewind, session listing, and other SDK features.
final class ClaudeProcess {
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var lineContinuation: AsyncStream<String>.Continuation?

    var isRunning: Bool { process?.isRunning ?? false }

    /// Resolves the source project root from the Xcode build environment.
    private static var projectRoot: String {
        // Method 1: Check for SRCROOT set at build time (via Info.plist)
        if let srcRoot = Bundle.main.object(forInfoDictionaryKey: "SOURCE_ROOT") as? String,
           FileManager.default.fileExists(atPath: srcRoot + "/SwiftTerminal/Claude/Bridge/claude-bridge.mjs") {
            return srcRoot
        }

        // Method 2: Known development path
        let knownPath = NSHomeDirectory() + "/Developer/Xcode/SwiftTerminal"
        if FileManager.default.fileExists(atPath: knownPath + "/SwiftTerminal/Claude/Bridge/claude-bridge.mjs") {
            return knownPath
        }

        // Method 3: Search common locations
        let searchPaths = [
            NSHomeDirectory() + "/Projects/SwiftTerminal",
            NSHomeDirectory() + "/Desktop/SwiftTerminal",
        ]
        for path in searchPaths {
            if FileManager.default.fileExists(atPath: path + "/SwiftTerminal/Claude/Bridge/claude-bridge.mjs") {
                return path
            }
        }

        return knownPath
    }

    /// Start the bridge process.
    /// Returns an async stream of JSON lines from stdout.
    func start() throws -> AsyncStream<String> {
        let proc = Process()

        // Find node executable
        for nodePath in ["/opt/homebrew/bin/node", "/usr/local/bin/node"] {
            if FileManager.default.fileExists(atPath: nodePath) {
                proc.executableURL = URL(filePath: nodePath)
                break
            }
        }

        let root = Self.projectRoot
        let bridgeScript = root + "/SwiftTerminal/Claude/Bridge/claude-bridge.mjs"

        guard FileManager.default.fileExists(atPath: bridgeScript) else {
            throw NSError(domain: "ClaudeProcess", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Bridge script not found at \(bridgeScript)"])
        }

        proc.arguments = [bridgeScript]

        // Environment: ensure node_modules and system paths are available
        var env = ProcessInfo.processInfo.environment
        env["NODE_PATH"] = root + "/node_modules"
        let extraPaths = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        if let existingPath = env["PATH"] {
            env["PATH"] = extraPaths + ":" + existingPath
        } else {
            env["PATH"] = extraPaths
        }
        env["TERM"] = "xterm-256color"
        env["HOME"] = env["HOME"] ?? NSHomeDirectory()
        proc.environment = env
        proc.currentDirectoryURL = URL(filePath: root)

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        self.process = proc
        self.stdinHandle = stdinPipe.fileHandleForWriting

        // Log stderr for debugging
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                print("[Claude Bridge stderr]", str)
            }
        }

        try proc.run()

        let handle = stdoutPipe.fileHandleForReading
        let stream = AsyncStream<String> { [weak self] continuation in
            self?.lineContinuation = continuation

            // Read stdout on a background thread
            Thread.detachNewThread {
                var buffer = Data()
                let newline = UInt8(ascii: "\n")

                while true {
                    let chunk = handle.availableData
                    if chunk.isEmpty { break }

                    buffer.append(chunk)

                    while let idx = buffer.firstIndex(of: newline) {
                        let lineData = buffer[buffer.startIndex..<idx]
                        buffer = Data(buffer[buffer.index(after: idx)...])
                        if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                            continuation.yield(line)
                        }
                    }
                }

                if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8), !line.isEmpty {
                    continuation.yield(line)
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                // Cleanup handled by terminate()
            }
        }

        return stream
    }

    /// Send a JSON command to the bridge via stdin.
    func sendCommand(_ command: String, params: [String: Any] = [:]) {
        guard let handle = stdinHandle else { return }

        var obj: [String: Any] = ["command": command]
        if !params.isEmpty {
            obj["params"] = params
        }

        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let jsonLine = String(data: data, encoding: .utf8) else { return }

        let lineData = (jsonLine + "\n").data(using: .utf8)!
        handle.write(lineData)
    }

    /// Terminate the bridge process.
    func terminate() {
        stdinHandle?.closeFile()
        stdinHandle = nil
        if let proc = process, proc.isRunning {
            proc.terminate()
        }
        process = nil
        lineContinuation?.finish()
        lineContinuation = nil
    }
}
