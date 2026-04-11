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
        }
        .frame(width: 480, height: 360)
    }
}

#Preview {
    SettingsView()
        .environment(UpdaterManager())
}
