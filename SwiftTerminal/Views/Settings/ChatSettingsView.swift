import SwiftUI

struct ChatSettingsView: View {
    @AppStorage("defaultChatMode") private var defaultChatMode: AgentProvider = .claude
    @AppStorage("defaultPermissionMode") private var defaultPermissionMode: PermissionMode = .bypassPermissions
    @AppStorage("enterToSendChat") private var enterToSendChat: Bool = false

    var body: some View {
        Form {
            Section {
                Picker("Default Chat Mode", selection: $defaultChatMode) {
                    ForEach(AgentProvider.allCases, id: \.self) { provider in
                        Label(provider.rawValue, image: provider.imageName)
                            .tag(provider)
                    }
                }
            } footer: {
                Text("The chat mode used when creating a new chat via the primary action.")
            }

            Section {
                Picker("Default Permission Mode", selection: $defaultPermissionMode) {
                    ForEach(PermissionMode.allCases) { mode in
                        Text(mode.label)
                            .tag(mode)
                    }
                }
            } footer: {
                Text(defaultPermissionMode.description)
            }

            Section {
                Toggle("Send message on Return", isOn: $enterToSendChat)
            } footer: {
                Text("When enabled, pressing Return sends the message. Hold Shift or Option for a newline. Cmd+Return always sends.")
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    ChatSettingsView()
}
