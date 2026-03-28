import SwiftUI

struct ElicitationPanelView: View {
    let elicitation: ElicitationRequest
    let onAccept: ([String: Any]?) -> Void
    let onDecline: () -> Void

    @State private var formValues: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            Text(elicitation.message)
                .font(.callout)
                .textSelection(.enabled)

            if elicitation.mode == .url, let url = elicitation.url {
                urlContent(url)
            } else if let schema = elicitation.requestedSchema {
                formContent(schema)
            }

            buttons
        }
        .padding(12)
        .background(Color.purple.opacity(0.05))
        .overlay(alignment: .top) { Divider() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "server.rack")
                .font(.caption)
                .foregroundStyle(.purple)

            Text("Input Required")
                .font(.caption)
                .fontWeight(.semibold)

            Text("from \(elicitation.serverName)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    private func urlContent(_ url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.right.square")
                Text("Open in Browser")
            }
            .font(.caption)
        }
    }

    private func formContent(_ schema: [String: Any]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let properties = schema["properties"] as? [String: Any] {
                ForEach(Array(properties.keys.sorted()), id: \.self) { key in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(key)
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        TextField(key, text: binding(for: key))
                            .textFieldStyle(.roundedBorder)
                            .font(.callout)
                    }
                }
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            Spacer()

            Button("Decline") {
                onDecline()
            }
            .keyboardShortcut(.escape, modifiers: [])
            .foregroundStyle(.red)

            Button("Submit") {
                let content = formValues.isEmpty ? nil : formValues as [String: Any]
                onAccept(content)
            }
            .keyboardShortcut(.return, modifiers: [])
            .buttonStyle(.borderedProminent)
            .tint(.purple)
        }
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { formValues[key, default: ""] },
            set: { formValues[key] = $0 }
        )
    }
}
