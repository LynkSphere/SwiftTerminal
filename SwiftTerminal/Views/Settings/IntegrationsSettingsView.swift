import SwiftUI

struct IntegrationsSettingsView: View {
    @Environment(AgentIntegrationStore.self) private var integrations

    var body: some View {
        @Bindable var integrations = integrations
        Form {
            Section {
                Toggle(isOn: $integrations.codexEnabled) {
                    Label {
                        Text("Codex")
                    } icon: {
                        Image(AgentProvider.codex.symbolName)
                            .foregroundStyle(AgentProvider.codex.color)
                    }
                }
                Toggle(isOn: $integrations.claudeEnabled) {
                    Label {
                        Text("Claude")
                    } icon: {
                        Image(AgentProvider.claude.symbolName)
                            .foregroundStyle(AgentProvider.claude.color)
                    }
                }
            } header: {
                Text("Integrations")
            } footer: {
                Text("Uses your installed command-line apps and their existing sign-in.")
            }
        }
        .formStyle(.grouped)
    }
}
