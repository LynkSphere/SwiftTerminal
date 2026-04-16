import SwiftUI

struct AboutView: View {
    private var appVersionAndBuild: String {
        let version = Bundle.main
            .infoDictionary?["CFBundleShortVersionString"] as? String ?? "N/A"
        let build = Bundle.main
            .infoDictionary?["CFBundleVersion"] as? String ?? "N/A"
        return "Version \(version) (\(build))"
    }

    private var copyright: String {
        let year = Calendar.current.component(.year, from: Date())
        return "© \(year) LynkSphere"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 80)
            Text("SwiftTerminal")
                .font(.title)
            VStack(spacing: 6) {
                Text(appVersionAndBuild)
                Text(copyright)
            }
            .font(.callout)
            VStack(spacing: 6) {
                Link("Developer Website",
                     destination: URL(string: "https://lynksphere.com")!)
                Link("GitHub Repository",
                     destination: URL(string: "https://github.com/LynkSphere/SwiftTerminal")!)
            }
            .foregroundStyle(.accent)
        }
        .padding()
        .frame(minWidth: 400, minHeight: 260)
    }
}

#Preview {
    AboutView()
}
