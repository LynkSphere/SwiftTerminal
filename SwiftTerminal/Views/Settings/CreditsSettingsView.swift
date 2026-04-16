import SwiftUI

struct CreditsSettingsView: View {
    var body: some View {
        Form {
            Section("Made By") {
                Link(destination: URL(string: "https://www.lynksphere.com")!) {
                    HStack(spacing: 10) {
                        Label {
                            Text("LynkSphere")
                            Text("Powering software around the world")
                        } icon: {
                            Image("LynkSphereLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 32, height: 32)
                        }

                        Spacer()

                        Image(systemName: "arrow.up.forward")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Section("Open Source") {
                CreditRow(
                    name: "SwiftTerm",
                    url: "https://github.com/migueldeicaza/SwiftTerm"
                )

                CreditRow(
                    name: "Highlightr",
                    url: "https://github.com/raspu/Highlightr"
                )
            }
        }
        .formStyle(.grouped)
    }
}

private struct CreditRow: View {
    let name: String
    let url: String

    var body: some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 10) {
                Label {
                    Text(name)
                    Text(url)
                } icon: {
                    EmptyView()
                }

                Spacer()

                Image(systemName: "arrow.up.forward")
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    CreditsSettingsView()
        .frame(width: 480, height: 400)
}
