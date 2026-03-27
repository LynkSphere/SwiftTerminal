import Foundation

enum GitError: Error {
    case gitUnavailable
    case commandFailed(command: String, message: String)
}

struct GitExecutor: Sendable {
    private let executableURL = URL(filePath: "/usr/bin/git")

    func execute<Command: GitCommand>(_ command: Command, at directoryURL: URL) async throws -> Command.Output {
        let result = try await self.run(arguments: command.arguments, at: directoryURL)

        guard result.terminationStatus == 0 else {
            let message = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitError.commandFailed(command: "git " + command.arguments.joined(separator: " "), message: message)
        }

        return try command.parse(output: result.standardOutput)
    }

    private func run(arguments: [String], at directoryURL: URL) async throws -> ExecutionResult {
        let process = Process()
        process.executableURL = self.executableURL
        process.arguments = arguments
        process.currentDirectoryURL = directoryURL

        let standardOutputPipe = Pipe()
        let standardErrorPipe = Pipe()
        process.standardOutput = standardOutputPipe
        process.standardError = standardErrorPipe

        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["LC_ALL"] = "C"
        process.environment = environment

        do {
            try process.run()
        } catch {
            throw GitError.gitUnavailable
        }

        // Read pipes and wait for exit concurrently in detached tasks to avoid
        // blocking the cooperative thread pool and to prevent pipe buffer deadlocks.
        let standardOutputHandle = standardOutputPipe.fileHandleForReading
        let standardErrorHandle = standardErrorPipe.fileHandleForReading
        async let standardOutputData = Task.detached(priority: .userInitiated) {
            standardOutputHandle.readDataToEndOfFile()
        }.value
        async let standardErrorData = Task.detached(priority: .userInitiated) {
            standardErrorHandle.readDataToEndOfFile()
        }.value
        async let terminationStatus = Task.detached(priority: .userInitiated) {
            process.waitUntilExit()
            return process.terminationStatus
        }.value

        return ExecutionResult(
            standardOutput: String(bytes: await standardOutputData, encoding: .utf8) ?? "",
            standardError: String(bytes: await standardErrorData, encoding: .utf8) ?? "",
            terminationStatus: await terminationStatus
        )
    }
}

private struct ExecutionResult: Sendable {
    var standardOutput: String
    var standardError: String
    var terminationStatus: Int32
}
