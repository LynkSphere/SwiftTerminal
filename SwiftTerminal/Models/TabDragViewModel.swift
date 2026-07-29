import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
final class TabDragViewModel {
    private static let detachThreshold: CGFloat = 32
    private static let tabBarTargetRange: ClosedRange<CGFloat> = -8...34

    private(set) var draggedTabID: UUID?
    private(set) var originalIndex: Int?
    private(set) var currentIndex: Int?
    private(set) var translation = CGSize.zero
    private(set) var isDetached = false
    private(set) var mergeTargetID: UUID?

    func update(
        terminal: Terminal,
        translation: CGSize,
        location: CGPoint,
        tabWidth: CGFloat,
        tabStride: CGFloat,
        terminals: [Terminal]
    ) {
        beginIfNeeded(terminal: terminal, terminals: terminals)
        guard draggedTabID == terminal.id, let originalIndex else { return }

        self.translation = translation

        if !isDetached, translation.height >= Self.detachThreshold {
            isDetached = true
            currentIndex = originalIndex
        }

        if isDetached {
            mergeTargetID = mergeTarget(
                at: location,
                sourceID: terminal.id,
                tabWidth: tabWidth,
                tabStride: tabStride,
                terminals: terminals
            )?.id
            return
        }

        let maximumIndex = max(terminals.count - 1, 0)
        let stepsMoved = Int((clampedHorizontalOffset(tabStride: tabStride, count: terminals.count) / tabStride).rounded())
        currentIndex = max(0, min(maximumIndex, originalIndex + stepsMoved))
        mergeTargetID = nil
    }

    func offset(for terminal: Terminal, at index: Int, tabStride: CGFloat, tabCount: Int) -> CGSize {
        if terminal.id == draggedTabID {
            if isDetached {
                return translation
            }
            return CGSize(
                width: clampedHorizontalOffset(tabStride: tabStride, count: tabCount),
                height: 0
            )
        }

        guard !isDetached, let originalIndex, let currentIndex else {
            return .zero
        }

        if originalIndex < currentIndex, index > originalIndex, index <= currentIndex {
            return CGSize(width: -tabStride, height: 0)
        }

        if originalIndex > currentIndex, index >= currentIndex, index < originalIndex {
            return CGSize(width: tabStride, height: 0)
        }

        return .zero
    }

    func finish(in workspace: Workspace, using appState: AppState) {
        defer { reset() }

        guard let draggedTabID,
              let source = workspace.terminals.first(where: { $0.id == draggedTabID }) else {
            return
        }

        if isDetached {
            guard let mergeTargetID,
                  let destination = workspace.terminals.first(where: { $0.id == mergeTargetID }) else {
                return
            }
            appState.moveTab(source, into: destination, axis: .horizontal)
            return
        }

        guard let originalIndex,
              let currentIndex,
              originalIndex != currentIndex else {
            return
        }

        var reordered = workspace.terminals
        reordered.remove(at: originalIndex)
        reordered.insert(source, at: currentIndex)
        workspace.reorderTerminals(reordered)
    }

    func reset() {
        draggedTabID = nil
        originalIndex = nil
        currentIndex = nil
        translation = .zero
        isDetached = false
        mergeTargetID = nil
    }

    private func beginIfNeeded(terminal: Terminal, terminals: [Terminal]) {
        guard draggedTabID != terminal.id,
              let index = terminals.firstIndex(where: { $0.id == terminal.id }) else {
            return
        }

        draggedTabID = terminal.id
        originalIndex = index
        currentIndex = index
        translation = .zero
        isDetached = false
        mergeTargetID = nil
    }

    private func clampedHorizontalOffset(tabStride: CGFloat, count: Int) -> CGFloat {
        guard let originalIndex else { return 0 }
        let minimum = -CGFloat(originalIndex) * tabStride
        let maximum = CGFloat(max(count - 1 - originalIndex, 0)) * tabStride
        return min(max(translation.width, minimum), maximum)
    }

    private func mergeTarget(
        at location: CGPoint,
        sourceID: UUID,
        tabWidth: CGFloat,
        tabStride: CGFloat,
        terminals: [Terminal]
    ) -> Terminal? {
        guard Self.tabBarTargetRange.contains(location.y), location.x >= 0 else {
            return nil
        }

        let targetIndex = Int(location.x / tabStride)
        guard terminals.indices.contains(targetIndex) else { return nil }

        let positionWithinSlot = location.x - CGFloat(targetIndex) * tabStride
        guard positionWithinSlot <= tabWidth else { return nil }

        let target = terminals[targetIndex]
        return target.id == sourceID ? nil : target
    }
}
