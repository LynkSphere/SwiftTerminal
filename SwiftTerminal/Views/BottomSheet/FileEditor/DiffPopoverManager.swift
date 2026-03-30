import AppKit

struct DiffPopoverLine {
    let content: String
    let kind: GitDiffLineKind  // .added or .removed
    let oldLineNumber: Int?
    let newLineNumber: Int?
}

enum DiffPopoverConstants {
    static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    static let lineHeight: CGFloat = 17
    static let gutterWidth: CGFloat = 40
    static let lineNumFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    static let verticalPadding: CGFloat = 8
}

enum DiffPopoverPresenter {
    static func showDiffPopover(for hunk: GutterDiffHunk, at point: NSPoint, in textView: EditorTextView) {
        let gutterWidth = EditorTextViewConstants.gutterWidth

        // Build line data for the popover text view
        let currentLines = textView.string.components(separatedBy: "\n")
        var popoverLines: [DiffPopoverLine] = []

        // Removed lines (from old content)
        if !hunk.oldContent.isEmpty {
            let oldLines = hunk.oldContent.components(separatedBy: "\n")
            for (i, line) in oldLines.enumerated() {
                popoverLines.append(DiffPopoverLine(
                    content: line,
                    kind: .removed,
                    oldLineNumber: hunk.oldStart + i,
                    newLineNumber: nil
                ))
            }
        }

        // Added/new lines (from current file)
        if hunk.kind == .added || hunk.kind == .modified, hunk.newCount > 0 {
            let start = max(hunk.newStart - 1, 0)
            let end = min(start + hunk.newCount, currentLines.count)
            for i in start..<end {
                popoverLines.append(DiffPopoverLine(
                    content: currentLines[i],
                    kind: .added,
                    oldLineNumber: nil,
                    newLineNumber: i + 1
                ))
            }
        }

        guard !popoverLines.isEmpty else { return }

        let popoverWidth: CGFloat = 560
        let maxPopoverHeight: CGFloat = 250

        let popoverTextView = DiffPopoverTextView()
        popoverTextView.configure(lines: popoverLines, fileExtension: textView.fileExtension, width: popoverWidth)

        let contentHeight: CGFloat
        if let lm = popoverTextView.layoutManager, let tc = popoverTextView.textContainer {
            lm.ensureLayout(for: tc)
            let usedRect = lm.usedRect(for: tc)
            contentHeight = usedRect.height + DiffPopoverConstants.verticalPadding * 2
        } else {
            contentHeight = CGFloat(popoverLines.count) * 17 + DiffPopoverConstants.verticalPadding * 2
        }

        let popoverHeight = min(contentHeight, maxPopoverHeight)

        let scrollView = NSScrollView()
        scrollView.documentView = popoverTextView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        popoverTextView.frame = NSRect(x: 0, y: 0, width: popoverWidth, height: contentHeight)
        popoverTextView.isVerticallyResizable = false

        let viewController = NSViewController()
        viewController.view = scrollView
        viewController.preferredContentSize = NSSize(width: popoverWidth, height: popoverHeight)

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = viewController

        let anchorRect = NSRect(x: gutterWidth - 2, y: point.y - 4, width: 4, height: 8)
        popover.show(relativeTo: anchorRect, of: textView, preferredEdge: .maxX)
    }
}

/// Draws diff lines with line number gutter and colored backgrounds.
final class DiffPopoverTextView: NSTextView {
    private var lineData: [(kind: GitDiffLineKind, oldNum: Int?, newNum: Int?)] = []

    func configure(lines: [DiffPopoverLine], fileExtension: String, width: CGFloat) {
        let constants = DiffPopoverConstants.self

        appearance = NSApp.effectiveAppearance

        isEditable = false
        isSelectable = true
        isRichText = false
        font = constants.font
        backgroundColor = .clear
        drawsBackground = false
        textColor = .labelColor
        textContainerInset = NSSize(width: constants.gutterWidth, height: constants.verticalPadding)

        isVerticallyResizable = true
        isHorizontallyResizable = true
        textContainer?.widthTracksTextView = false
        textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        minSize = NSSize(width: width, height: 0)
        autoresizingMask = []

        lineData = lines.map { (kind: $0.kind, oldNum: $0.oldLineNumber, newNum: $0.newLineNumber) }

        let source = lines.map(\.content).joined(separator: "\n")
        let attributed = SyntaxHighlighter.highlight(source, fileExtension: fileExtension)
        textStorage?.setAttributedString(attributed)

        layoutManager?.ensureLayout(forCharacterRange: NSRange(location: 0, length: (source as NSString).length))
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            appearance = window.effectiveAppearance
            needsDisplay = true
        }
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)

        guard let layoutManager, let textContainer else { return }

        let constants = DiffPopoverConstants.self
        let text = string as NSString
        let containerOrigin = textContainerOrigin
        let gw = constants.gutterWidth

        guard text.length > 0 else { return }

        let fullRange = layoutManager.glyphRange(forBoundingRect: rect, in: textContainer)
        let charRange = layoutManager.characterRange(forGlyphRange: fullRange, actualGlyphRange: nil)

        let lineNumAttrs: [NSAttributedString.Key: Any] = [
            .font: constants.lineNumFont,
            .foregroundColor: NSColor.secondaryLabelColor,
        ]

        let colWidth: CGFloat = (gw - 6) / 2

        text.enumerateSubstrings(in: charRange, options: [.byLines, .substringNotRequired]) { _, substringRange, enclosingRange, _ in
            let lineIdx = self.lineIndex(forCharacterIndex: substringRange.location)
            guard lineIdx < self.lineData.count else { return }

            let glyphRange = layoutManager.glyphRange(forCharacterRange: enclosingRange, actualCharacterRange: nil)
            var lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            lineRect.origin.y += containerOrigin.y

            let data = self.lineData[lineIdx]
            let bgColor: NSColor = data.kind.color.withAlphaComponent(0.12)
            var fullLineRect = lineRect
            fullLineRect.origin.x = gw
            fullLineRect.size.width = self.bounds.width - gw
            bgColor.setFill()
            fullLineRect.fill()

            let y = lineRect.minY

            if let old = data.oldNum {
                let str = "\(old)" as NSString
                let size = str.size(withAttributes: lineNumAttrs)
                str.draw(at: NSPoint(x: colWidth - size.width, y: y), withAttributes: lineNumAttrs)
            }

            if let new = data.newNum {
                let str = "\(new)" as NSString
                let size = str.size(withAttributes: lineNumAttrs)
                str.draw(at: NSPoint(x: colWidth + 2 + (colWidth - size.width), y: y), withAttributes: lineNumAttrs)
            }
        }
    }

    private func lineIndex(forCharacterIndex index: Int) -> Int {
        let text = string as NSString
        var lineIdx = 0
        var i = 0
        while i < index && i < text.length {
            if text.character(at: i) == 0x0A { lineIdx += 1 }
            i += 1
        }
        return lineIdx
    }
}
