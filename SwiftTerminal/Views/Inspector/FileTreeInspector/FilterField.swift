import SwiftUI

struct FilterField<Trailing: View>: View {
    @Binding var text: String
    @ViewBuilder var trailing: Trailing

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: text.isEmpty
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(text.isEmpty ? .secondary : Color.accentColor)
                .font(.caption)

            TextField("Filter", text: $text)
                .textFieldStyle(.plain)
                .font(.caption)
                .focused($isFocused)

            trailing
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.quaternary, in: Capsule())
    }
}
