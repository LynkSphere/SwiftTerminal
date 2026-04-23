import Foundation
import ACP

extension ACPSession {
    func launchAndCreateSession() async {
        isConnecting = true
        error = nil

        do {
            let newClient = try await launchAndInitialize()
            try await createNewSession(client: newClient)
        } catch {
            isConnecting = false
            self.error = error.localizedDescription
        }
    }

    func relaunchAndLoadSession(_ sessionId: SessionId) async {
        notificationTask?.cancel()
        notificationTask = nil
        let oldClient = client
        setClient(nil)
        setSessionId(nil)
        isConnected = false
        isConnecting = true
        error = nil

        if let oldClient {
            await oldClient.terminate()
            try? await Task.sleep(for: .milliseconds(500))
        }

        do {
            isReplaying = true
            let newClient = try await launchAndInitialize()
            listenForNotifications(client: newClient)

            let response = try await newClient.loadSession(
                sessionId: sessionId,
                cwd: workingDirectory,
                mcpServers: []
            )
            setSessionId(response.sessionId ?? sessionId)

            // Let queued replay notifications drain before re-opening the
            // update handler.
            try? await Task.sleep(for: .seconds(1))
            isReplaying = false

            isConnected = true
            isConnecting = false
            onConnected?()
        } catch {
            isReplaying = false
            isConnecting = false
            self.error = error.localizedDescription
        }
    }

    func launchAndInitialize() async throws -> Client {
        let newClient = Client()
        await newClient.setDelegate(autoApproveDelegate)
        setClient(newClient)

        try await newClient.launch(
            agentPath: "/usr/bin/env",
            arguments: ["npx", provider.acpPackage],
            workingDirectory: workingDirectory
        )

        _ = try await newClient.initialize(
            capabilities: ClientCapabilities(
                fs: FileSystemCapabilities(readTextFile: false, writeTextFile: false),
                terminal: false
            ),
            clientInfo: ClientInfo(
                name: "SwiftTerminal",
                title: "Swift Terminal",
                version: "1.0.0"
            ),
            timeout: 120
        )

        return newClient
    }

    func createNewSession(client: Client) async throws {
        let session = try await client.newSession(
            workingDirectory: workingDirectory,
            timeout: 60
        )
        setSessionId(session.sessionId)
        isConnected = true
        isConnecting = false
        listenForNotifications(client: client)
        onConnected?()
    }

    func terminateAndRelaunch() async {
        notificationTask?.cancel()
        notificationTask = nil
        let oldClient = client
        setClient(nil)
        setSessionId(nil)
        isConnected = false

        if let oldClient {
            await oldClient.terminate()
            try? await Task.sleep(for: .milliseconds(500))
        }

        do {
            let newClient = try await launchAndInitialize()
            try await createNewSession(client: newClient)
        } catch {
            isConnecting = false
            self.error = error.localizedDescription
        }
    }
}
