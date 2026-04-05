import AppKit
import SwiftUI

struct DiffTextEditor: NSViewRepresentable {
    let presentation: GitDiffPresentation
    let fileExtension: String
    let hunks: [DiffHunk]
    let reference: GitDiffReference
    let onReload: () async -> Void
    @Environment(\.editorFontSize) private var fontSize

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.autoresizesSubviews = true

        let minimapWidth: CGFloat = 28
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.autoresizingMask = [.width, .height]

        let textContainer = NSTextContainer(
            containerSize: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        )
        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = false

        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)

        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)

        let contentSize = scrollView.contentSize
        let textView = EditorTextView(frame: NSRect(origin: .zero, size: contentSize), textContainer: textContainer)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.editorFontSize = fontSize
        textView.lineNumberFontSize = fontSize - 1
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: EditorTextViewConstants.diffGutterWidth, height: 4)
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        // Horizontal scrolling
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.autoresizingMask = []

        // Diff mode data
        textView.diffLineKinds = presentation.lineKinds
        textView.diffLineNumbers = presentation.lineNumbers
        textView.fileExtension = fileExtension

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.hunks = hunks
        context.coordinator.reference = reference
        context.coordinator.presentation = presentation
        context.coordinator.onReload = onReload
        context.coordinator.minimapWidth = minimapWidth
        context.coordinator.buildHunkLookup()

        // Gutter click handler
        let coordinator = context.coordinator
        textView.diffGutterClickHandler = { [weak coordinator] renderLine, point in
            coordinator?.handleGutterClick(renderLine: renderLine, at: point)
        }

        // Minimap (thicker for diff view)
        let minimap = EditorMinimap()
        minimap.autoresizingMask = [.minXMargin, .height]
        minimap.totalLines = max(presentation.string.components(separatedBy: "\n").count, 1)
        let diffColors: [Int: NSColor] = presentation.lineKinds.mapValues { $0.color }
        minimap.setMarkers(diffColors)
        minimap.onScrollToFraction = { [weak scrollView] fraction in
            guard let scrollView, let doc = scrollView.documentView else { return }
            let totalH = doc.frame.height
            let visH = scrollView.contentView.bounds.height
            let targetY = max(0, min(fraction * totalH - visH / 2, totalH - visH))
            scrollView.contentView.setBoundsOrigin(
                NSPoint(x: scrollView.contentView.bounds.origin.x, y: targetY)
            )
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        context.coordinator.minimap = minimap

        // Layout
        container.addSubview(scrollView)
        container.addSubview(minimap)

        // Observe scroll for minimap viewport
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator, selector: #selector(Coordinator.scrollDidChange(_:)),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView
        )

        // Syntax highlight
        let highlighted = SyntaxHighlighter.highlight(
            presentation.string, fileExtension: fileExtension, fontSize: fontSize
        )
        textView.textStorage?.setAttributedString(highlighted)

        // Word-level inline diff highlights
        Self.applyInlineHighlights(to: textView.textStorage!, lineKinds: presentation.lineKinds)

        // Scroll to first change, keeping gutter visible
        DispatchQueue.main.async {
            if let firstLine = presentation.firstChangedLine {
                textView.scrollToLine(max(firstLine - 3, 1))
            }
            scrollView.contentView.setBoundsOrigin(
                NSPoint(x: 0, y: scrollView.contentView.bounds.origin.y)
            )
            minimap.updateViewport(from: scrollView)
        }

        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        let scrollView = context.coordinator.scrollView
        let minimap = context.coordinator.minimap
        let minimapWidth = context.coordinator.minimapWidth

        // Update layout
        let bounds = container.bounds
        scrollView?.frame = NSRect(x: 0, y: 0, width: bounds.width - minimapWidth, height: bounds.height)
        minimap?.frame = NSRect(x: bounds.width - minimapWidth, y: 0, width: minimapWidth, height: bounds.height)

        textView.needsDisplay = true
    }

    // MARK: - Inline Word-Level Highlights

    private static func applyInlineHighlights(to textStorage: NSTextStorage, lineKinds: [Int: GitDiffLineKind]) {
        let text = textStorage.string as NSString
        guard text.length > 0 else { return }

        // Build line starts (0-based index → character offset)
        var lineStarts: [Int] = [0]
        for i in 0..<text.length {
            if text.character(at: i) == 0x0A {
                lineStarts.append(i + 1)
            }
        }

        let lineCount = lineStarts.count

        func lineContent(_ lineIdx: Int) -> String {
            // lineIdx is 0-based (corresponds to 1-based line number lineIdx+1)
            guard lineIdx < lineStarts.count else { return "" }
            let start = lineStarts[lineIdx]
            let end: Int
            if lineIdx + 1 < lineStarts.count {
                end = lineStarts[lineIdx + 1] - 1 // exclude \n
            } else {
                end = text.length
            }
            guard end > start else { return "" }
            return text.substring(with: NSRange(location: start, length: end - start))
        }

        // Scan for consecutive removed→added blocks (1-based line numbers)
        var i = 1
        while i <= lineCount {
            guard lineKinds[i] == .removed else { i += 1; continue }
            let removedStart = i
            while i <= lineCount && lineKinds[i] == .removed { i += 1 }
            let removedEnd = i // exclusive

            guard i <= lineCount && lineKinds[i] == .added else { continue }
            let addedStart = i
            while i <= lineCount && lineKinds[i] == .added { i += 1 }
            let addedEnd = i // exclusive

            let pairCount = min(removedEnd - removedStart, addedEnd - addedStart)
            for p in 0..<pairCount {
                let ri = removedStart + p // 1-based
                let ai = addedStart + p

                let riIdx = ri - 1 // 0-based
                let aiIdx = ai - 1
                guard riIdx < lineStarts.count && aiIdx < lineStarts.count else { continue }

                let oldLine = lineContent(riIdx)
                let newLine = lineContent(aiIdx)
                let (oldRange, newRange) = inlineDiffRanges(old: oldLine, new: newLine)

                if let r = oldRange {
                    let nsRange = NSRange(location: lineStarts[riIdx] + r.lowerBound, length: r.upperBound - r.lowerBound)
                    if nsRange.upperBound <= textStorage.length {
                        textStorage.addAttribute(.backgroundColor, value: NSColor.systemRed.withAlphaComponent(0.22), range: nsRange)
                    }
                }
                if let r = newRange {
                    let nsRange = NSRange(location: lineStarts[aiIdx] + r.lowerBound, length: r.upperBound - r.lowerBound)
                    if nsRange.upperBound <= textStorage.length {
                        textStorage.addAttribute(.backgroundColor, value: NSColor.systemGreen.withAlphaComponent(0.22), range: nsRange)
                    }
                }
            }
        }
    }

    private static func inlineDiffRanges(old: String, new: String) -> (Range<Int>?, Range<Int>?) {
        let oldChars: [unichar] = Array(old.utf16)
        let newChars: [unichar] = Array(new.utf16)

        var prefixLen = 0
        let minLen = min(oldChars.count, newChars.count)
        while prefixLen < minLen && oldChars[prefixLen] == newChars[prefixLen] {
            prefixLen += 1
        }

        let maxSuffix = min(oldChars.count - prefixLen, newChars.count - prefixLen)
        var suffixLen = 0
        while suffixLen < maxSuffix {
            let oldIdx = oldChars.count - 1 - suffixLen
            let newIdx = newChars.count - 1 - suffixLen
            guard oldChars[oldIdx] == newChars[newIdx] else { break }
            suffixLen += 1
        }

        let oldDiffEnd = oldChars.count - suffixLen
        let newDiffEnd = newChars.count - suffixLen
        let oldLen = oldDiffEnd - prefixLen
        let newLen = newDiffEnd - prefixLen
        if oldLen <= 0 && newLen <= 0 { return (nil, nil) }

        let oldRange: Range<Int>? = oldLen > 0 ? prefixLen..<oldDiffEnd : nil
        let newRange: Range<Int>? = newLen > 0 ? prefixLen..<newDiffEnd : nil
        return (oldRange, newRange)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        weak var textView: EditorTextView?
        weak var scrollView: NSScrollView?
        weak var minimap: EditorMinimap?
        var minimapWidth: CGFloat = 28
        var presentation: GitDiffPresentation?
        var hunks: [DiffHunk] = []
        var reference: GitDiffReference?
        var onReload: (() async -> Void)?

        // Lookup: new/old line number → hunk index
        private var newLineToHunkIndex: [Int: Int] = [:]
        private var oldLineToHunkIndex: [Int: Int] = [:]

        @objc func scrollDidChange(_ notification: Notification) {
            guard let scrollView else { return }
            minimap?.updateViewport(from: scrollView)
        }

        func buildHunkLookup() {
            newLineToHunkIndex.removeAll()
            oldLineToHunkIndex.removeAll()
            for (index, hunk) in hunks.enumerated() {
                for line in hunk.lines where line.kind != nil {
                    if let newNum = line.newLineNumber {
                        newLineToHunkIndex[newNum] = index
                    }
                    if let oldNum = line.oldLineNumber {
                        oldLineToHunkIndex[oldNum] = index
                    }
                }
            }
        }

        func handleGutterClick(renderLine: Int, at point: NSPoint) {
            guard let textView, let presentation, let reference else { return }
            guard presentation.lineKinds[renderLine] != nil else { return }

            let lineNums = presentation.lineNumbers[renderLine]
            var hunkIndex: Int?
            if let newNum = lineNums?.new { hunkIndex = newLineToHunkIndex[newNum] }
            if hunkIndex == nil, let oldNum = lineNums?.old { hunkIndex = oldLineToHunkIndex[oldNum] }

            guard let idx = hunkIndex, idx < hunks.count else { return }
            if case .commit = reference.stage { return }

            showContextMenu(for: hunks[idx], reference: reference, at: point, in: textView)
        }

        private func showContextMenu(for hunk: DiffHunk, reference: GitDiffReference, at point: NSPoint, in view: NSView) {
            let menu = NSMenu()

            switch reference.stage {
            case .unstaged:
                let stageItem = NSMenuItem(title: "Stage Hunk", action: #selector(menuStageHunk(_:)), keyEquivalent: "")
                stageItem.target = self
                stageItem.representedObject = hunk
                menu.addItem(stageItem)

                menu.addItem(.separator())

                let discardItem = NSMenuItem(title: "Discard Hunk", action: #selector(menuDiscardHunk(_:)), keyEquivalent: "")
                discardItem.target = self
                discardItem.representedObject = hunk
                menu.addItem(discardItem)

            case .staged:
                let unstageItem = NSMenuItem(title: "Unstage Hunk", action: #selector(menuUnstageHunk(_:)), keyEquivalent: "")
                unstageItem.target = self
                unstageItem.representedObject = hunk
                menu.addItem(unstageItem)

            case .commit:
                return
            }

            menu.popUp(positioning: nil, at: point, in: view)
        }

        @objc private func menuStageHunk(_ sender: NSMenuItem) {
            guard let hunk = sender.representedObject as? DiffHunk, let reference else { return }
            applyHunk(hunk, reverse: false, cached: true, at: reference.repositoryRootURL)
        }

        @objc private func menuUnstageHunk(_ sender: NSMenuItem) {
            guard let hunk = sender.representedObject as? DiffHunk, let reference else { return }
            applyHunk(hunk, reverse: true, cached: true, at: reference.repositoryRootURL)
        }

        @objc private func menuDiscardHunk(_ sender: NSMenuItem) {
            guard let hunk = sender.representedObject as? DiffHunk, let reference else { return }
            applyHunk(hunk, reverse: true, cached: false, at: reference.repositoryRootURL)
        }

        private func applyHunk(_ hunk: DiffHunk, reverse: Bool, cached: Bool, at root: URL) {
            Task {
                do {
                    try await GitRepository.shared.applyPatch(
                        hunk.patchText, reverse: reverse, cached: cached, at: root
                    )
                    await onReload?()
                } catch {
                    print("Failed to apply hunk: \(error)")
                }
            }
        }
    }
}
