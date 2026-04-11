import SwiftUI

struct LynkSphereByline: View {
    var animated: Bool = false
    @State private var pulse = false

    var body: some View {
        Link(destination: URL(string: "https://www.lynksphere.com")!) {
            HStack(spacing: 6) {
                Text("by")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Image("LynkSphereLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 18)
                    .scaleEffect(animated && pulse ? 1.06 : 1.0)
                    .rotationEffect(.degrees(animated && pulse ? 4 : -4))

                Text("LynkSphere")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .foregroundStyle(.primary)
        .onAppear {
            guard animated else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        LynkSphereByline()
        LynkSphereByline(animated: true)
    }
    .padding()
}
