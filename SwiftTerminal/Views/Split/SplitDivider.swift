import SwiftUI

/// Draggable divider between two panes, reporting incremental pixel deltas.
struct SplitDivider: View {
    let axis: SplitAxis
    let onDrag: (CGFloat) -> Void
    @State private var lastTranslation: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(
                width: axis == .horizontal ? 8 : nil,
                height: axis == .vertical ? 8 : nil
            )
            .frame(
                maxWidth: axis == .vertical ? .infinity : nil,
                maxHeight: axis == .horizontal ? .infinity : nil
            )
            .overlay {
                Rectangle()
                    .fill(.separator)
                    .frame(
                        width: axis == .horizontal ? 1 : nil,
                        height: axis == .vertical ? 1 : nil
                    )
            }
            .contentShape(Rectangle())
            .pointerStyle(axis == .horizontal ? .columnResize : .rowResize)
            .gesture(
                // Global space: the divider moves as it's dragged, so a `.local`
                // translation would chase its own shifting frame and lag the cursor.
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let t = axis == .horizontal ? value.translation.width : value.translation.height
                        onDrag(t - lastTranslation)
                        lastTranslation = t
                    }
                    .onEnded { _ in lastTranslation = 0 }
            )
    }
}
