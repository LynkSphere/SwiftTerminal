import SwiftUI

struct FilterField<Trailing: View>: View {
    @Binding var text: String
    @ViewBuilder var trailing: Trailing

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField("Filter", text: $text)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .focused($isFocused)

            trailing
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(.quaternary, in: Capsule())
    }
}
