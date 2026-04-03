import Foundation

@Observable
final class CommandRunner {

    private static var registry: [UUID: CommandRunner] = [:]

    static func runner(for id: UUID) -> CommandRunner {
        if let existing = registry[id] { return existing }
        let runner = CommandRunner()
        registry[id] = runner
        return runner
    }

    static func remove(for id: UUID) {
        registry[id]?.stop()
        registry.removeValue(forKey: id)
    }

    private(set) var process: Process?
    private(set) var pipe: Pipe?
    private(set) var output: String = ""
    private(set) var exitCode: Int32?

    var isRunning: Bool { process?.isRunning == true }

    func run(command: String, in directory: URL) {
        stop()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", command]
        process.currentDirectoryURL = directory

        var env = ProcessInfo.processInfo.environment
        env["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        if env["PATH"] == nil {
            env["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        }
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        self.process = process
        self.pipe = pipe
        self.output = ""
        self.exitCode = nil

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                self?.output.append(text)
            }
        }

        process.terminationHandler = { [weak self] proc in
            Task { @MainActor [weak self] in
                self?.exitCode = proc.terminationStatus
                pipe.fileHandleForReading.readabilityHandler = nil
            }
        }

        do {
            try process.run()
        } catch {
            output = "Failed to start: \(error.localizedDescription)"
            exitCode = -1
        }
    }

    func stop() {
        if let process, process.isRunning {
            let pid = process.processIdentifier
            kill(-pid, SIGTERM)
        }
        pipe?.fileHandleForReading.readabilityHandler = nil
        process = nil
        pipe = nil
    }
}
