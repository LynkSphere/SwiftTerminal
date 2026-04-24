import Foundation
import ACP
import ACPModel

final class ACPSessionDelegate: ClientDelegate, @unchecked Sendable {

    // MARK: - Permissions

    /// Called when the agent requests permission for a tool call.
    /// Wire this up to a UI prompt later for non-bypass permission modes.
    func handlePermissionRequest(request: RequestPermissionRequest) async throws -> RequestPermissionResponse {
        return RequestPermissionResponse(outcome: PermissionOutcome(cancelled: true))
    }

    // MARK: - File System

    func handleFileReadRequest(_ path: String, sessionId: String, line: Int?, limit: Int?) async throws -> ReadTextFileResponse {
        throw ACPDelegateError.notSupported
    }

    func handleFileWriteRequest(_ path: String, content: String, sessionId: String) async throws -> WriteTextFileResponse {
        throw ACPDelegateError.notSupported
    }

    // MARK: - Terminal

    func handleTerminalCreate(command: String, sessionId: String, args: [String]?, cwd: String?, env: [EnvVariable]?, outputByteLimit: Int?) async throws -> CreateTerminalResponse {
        throw ACPDelegateError.notSupported
    }

    func handleTerminalOutput(terminalId: TerminalId, sessionId: String) async throws -> TerminalOutputResponse {
        throw ACPDelegateError.notSupported
    }

    func handleTerminalWaitForExit(terminalId: TerminalId, sessionId: String) async throws -> WaitForExitResponse {
        throw ACPDelegateError.notSupported
    }

    func handleTerminalKill(terminalId: TerminalId, sessionId: String) async throws -> KillTerminalResponse {
        throw ACPDelegateError.notSupported
    }

    func handleTerminalRelease(terminalId: TerminalId, sessionId: String) async throws -> ReleaseTerminalResponse {
        throw ACPDelegateError.notSupported
    }
}

enum ACPDelegateError: Error {
    case notSupported
}
