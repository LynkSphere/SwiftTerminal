import SwiftUI

struct ChatSettingsView: View {
    @AppStorage("defaultChatMode") private var defaultChatMode: AgentProvider = .claude

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
        }
        .formStyle(.grouped)
    }
}

#Preview {
    ChatSettingsView()
}
