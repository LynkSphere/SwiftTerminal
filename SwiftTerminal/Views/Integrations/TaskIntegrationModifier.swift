import SwiftUI

struct TaskIntegrationModifier: ViewModifier {
    @Environment(AppState.self) private var appState
    @Environment(AgentIntegrationStore.self) private var integrations
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onChange(of: appState.selectedSession?.id, initial: true) {
                integrations.setViewedThread(scenePhase == .active ? appState.selectedSession?.id : nil)
            }
            .onChange(of: scenePhase) {
                integrations.setViewedThread(scenePhase == .active ? appState.selectedSession?.id : nil)
            }
            .onChange(of: integrations.threads, initial: true) {
                appState.updateSessions(integrations.threads, enabledProviders: integrations.enabledProviders)
            }
            .task(id: [integrations.codexEnabled, integrations.claudeEnabled, scenePhase == .active]) {
                appState.updateSessions(integrations.threads, enabledProviders: integrations.enabledProviders)
                if scenePhase == .active || !integrations.isEnabled { await integrations.refresh() }
            }
    }
}
