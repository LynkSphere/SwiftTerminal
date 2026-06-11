import SwiftUI

/// Recursively lays out a tab's `PaneNode` tree: leaves render a terminal,
/// branches split their space among children with draggable dividers.
struct SplitTreeView: View {
    let node: PaneNode
    let tab: Terminal
    let appState: AppState

    private let dividerThickness: CGFloat = 8

    var body: some View {
        if let terminal = node.terminal {
            PaneView(terminal: terminal, tab: tab, appState: appState)
        } else {
            branchBody
        }
    }

    private var branchBody: some View {
        GeometryReader { geo in
            let count = node.children.count
            let totalLength = node.axis == .horizontal ? geo.size.width : geo.size.height
            let available = max(totalLength - dividerThickness * CGFloat(max(count - 1, 0)), 0)

            stack {
                ForEach(Array(node.children.enumerated()), id: \.element.id) { index, child in
                    let length = available * fraction(at: index)
                    SplitTreeView(node: child, tab: tab, appState: appState)
                        .frame(
                            width: node.axis == .horizontal ? length : geo.size.width,
                            height: node.axis == .vertical ? length : geo.size.height
                        )

                    if index < count - 1 {
                        SplitDivider(axis: node.axis) { deltaPixels in
                            adjustFraction(at: index, byPixels: deltaPixels, total: available)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func stack<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if node.axis == .horizontal {
            HStack(spacing: 0) { content() }
        } else {
            VStack(spacing: 0) { content() }
        }
    }

    private func fraction(at index: Int) -> Double {
        node.fractions.indices.contains(index) ? node.fractions[index] : 1.0 / Double(max(node.children.count, 1))
    }

    private func adjustFraction(at i: Int, byPixels deltaPixels: CGFloat, total: CGFloat) {
        guard total > 0, node.fractions.indices.contains(i + 1) else { return }
        let delta = Double(deltaPixels / total)
        let minFraction = 0.1
        var a = node.fractions[i] + delta
        var b = node.fractions[i + 1] - delta
        if a < minFraction { b -= (minFraction - a); a = minFraction }
        if b < minFraction { a -= (minFraction - b); b = minFraction }
        node.fractions[i] = a
        node.fractions[i + 1] = b
    }
}
