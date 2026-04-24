import SwiftUI

struct ChatSettingsView: View {
    @AppStorage("defaultChatMode") private var defaultChatMode: AgentProvider = .claude
    @AppStorage("defaultPermissionMode") private var defaultPermissionMode: PermissionMode = .bypassPermissions

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
        }
        .formStyle(.grouped)
    }
}

#Preview {
    ChatSettingsView()
}
