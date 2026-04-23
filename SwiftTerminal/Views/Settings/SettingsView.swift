import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            UpdatesSettingsView()
                .tabItem {
                    Label("Updates", systemImage: "arrow.down.circle")
                }

            ChatSettingsView()
                .tabItem {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right")
                }

            ShortcutsSettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }

            CreditsSettingsView()
                .tabItem {
                    Label("Credits", systemImage: "heart")
                }
        }
        .frame(width: 480, height: 400)
    }
}

#Preview {
    SettingsView()
        .environment(UpdaterManager())
}
