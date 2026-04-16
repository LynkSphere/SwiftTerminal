import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage("hideTabBarWithSingleTab") private var hideTabBarWithSingleTab = false
    @AppStorage("hideSettingsButton") private var hideSettingsButton = false
    @AppStorage("editorWrapLines") private var editorWrapLines = true
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage(TerminalProcessRegistry.fontSizeKey) private var terminalFontSize: Double = Double(TerminalProcessRegistry.defaultFontSize)

    var body: some View {
        Form {
            Section("Appearance") {
                Toggle("Hide tab bar when only one tab is open", isOn: $hideTabBarWithSingleTab)
                Toggle("Hide settings button from sidebar", isOn: $hideSettingsButton)
            }

            Section {
                LabeledContent {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { terminalFontSize },
                                set: { terminalFontSize = (($0 * 2).rounded()) / 2 }
                            ),
                            in: Double(TerminalProcessRegistry.minFontSize)...Double(TerminalProcessRegistry.maxFontSize)
                        )
                        Text(String(format: "%.1f", terminalFontSize))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 25, alignment: .trailing)
                    }
                } label: {
                    Text("Font size")
                }
            } header: {
                Text("Terminal")
            }
            .onChange(of: terminalFontSize) { _, newValue in
                TerminalProcessRegistry.applyFontSizeToAll(CGFloat(newValue))
            }

            Section {
                Toggle("Wrap long lines", isOn: $editorWrapLines)
            } header: {
                Text("Editor")
            } footer: {
                Text("When enabled, lines that exceed the editor width wrap to the next line instead of scrolling horizontally.")
            }

            #if DEBUG
            Section {
                LabeledContent("Reset Onboarding") {
                    Button("Launch") {
                        hasCompletedOnboarding = false
                    }
                }
            } header: {
                Text("Debug")
            } footer: {
                Text("Resets the onboarding flag so the welcome sheet appears again on next launch.")
            }
            #endif
        }
        .formStyle(.grouped)
    }
}

#Preview {
    GeneralSettingsView()
}
