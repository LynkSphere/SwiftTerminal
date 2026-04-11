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
        .frame(width: 480, height: 260)
    }
}

private struct GeneralSettingsView: View {
    @AppStorage("hideTabBarWithSingleTab") private var hideTabBarWithSingleTab = false

    var body: some View {
        Form {
            Section {
                Toggle("Hide tab bar when only one tab is open", isOn: $hideTabBarWithSingleTab)
            } header: {
                Text("Tabs")
            } footer: {
                Text("When enabled, the tab bar is hidden in workspaces that have a single terminal tab.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct UpdatesSettingsView: View {
    @Environment(UpdaterManager.self) private var updater

    /// User-facing labels for the supported check intervals.
    private let intervals: [(label: String, seconds: TimeInterval)] = [
        ("Hourly", 3_600),
        ("Daily", 86_400),
        ("Weekly", 604_800),
        ("Monthly", 2_592_000),
    ]

    var body: some View {
        @Bindable var updater = updater

        Form {
            Section {
                Toggle("Automatically check for updates", isOn: $updater.automaticallyChecksForUpdates)

                Picker("Check frequency", selection: $updater.updateCheckInterval) {
                    ForEach(intervals, id: \.seconds) { interval in
                        Text(interval.label).tag(interval.seconds)
                    }
                }
                .disabled(!updater.automaticallyChecksForUpdates)

                HStack {
                    Spacer()
                    Button("Check for Updates…") {
                        updater.checkForUpdates()
                    }
                    .disabled(!updater.canCheckForUpdates)
                }
            } header: {
                Text("Software Updates")
            } footer: {
                Text("SwiftTerminal uses Sparkle to download and install updates automatically.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    SettingsView()
        .environment(UpdaterManager())
}
