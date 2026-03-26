import AppKit

enum EditorTextViewConstants {
    static let gutterWidth: CGFloat = 44
    static let markerBarWidth: CGFloat = 3
}

// MARK: - Editor Text View with Gutter

final class EditorTextView: NSTextView {
    var gutterDiff: GutterDiffResult = .empty
    var fileExtension: String = ""

    private let lineNumberFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)

        guard let layoutManager, let textContainer else { return }

        let gutterWidth = EditorTextViewConstants.gutterWidth
        let markerBarWidth = EditorTextViewConstants.markerBarWidth
        let containerOrigin = textContainerOrigin
        let text = string as NSString

        // Draw gutter background TODO: not doing anything rn
        let gutterRect = NSRect(x: 0, y: rect.minY, width: gutterWidth, height: rect.height)
        NSColor.controlBackgroundColor.withAlphaComponent(0.5).setFill()
        gutterRect.fill()

        // Draw gutter separator
        NSColor.separatorColor.withAlphaComponent(0.15).setStroke()
        NSBezierPath.strokeLine(
            from: NSPoint(x: gutterWidth - 0.5, y: rect.minY),
            to: NSPoint(x: gutterWidth - 0.5, y: rect.maxY)
        )

        guard text.length > 0 else { return }

        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: rect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        let lineNumAttrs: [NSAttributedString.Key: Any] = [
            .font: lineNumberFont,
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]

        // Count lines before visible range
        var startLineNumber = 1
        if visibleCharRange.location > 0 {
            let preText = text.substring(to: visibleCharRange.location)
            startLineNumber = preText.components(separatedBy: "\n").count
        }

        var lineNumber = startLineNumber
        var charIndex = visibleCharRange.location
        let endChar = NSMaxRange(visibleCharRange)

        while charIndex <= endChar && charIndex < text.length {
            let lineRange = text.lineRange(for: NSRange(location: charIndex, length: 0))
            let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)

            if glyphRange.location != NSNotFound {
                var lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                lineRect.origin.x += containerOrigin.x
                lineRect.origin.y += containerOrigin.y

                if lineRect.minY + lineRect.height >= rect.minY && lineRect.minY <= rect.maxY {
                    // Draw line number right-aligned
                    let numStr = "\(lineNumber)" as NSString
                    let size = numStr.size(withAttributes: lineNumAttrs)
                    let x = gutterWidth - markerBarWidth - size.width - 6
                    let y = lineRect.minY + (lineRect.height - size.height) / 2
                    numStr.draw(at: NSPoint(x: x, y: y), withAttributes: lineNumAttrs)

                    // Draw git change marker bar
                    if let kind = gutterDiff.markers[lineNumber] {
                        kind.color.setFill()
                        if kind == .deleted {
                            NSRect(
                                x: gutterWidth - markerBarWidth - 1,
                                y: lineRect.minY - 1,
                                width: markerBarWidth + 1,
                                height: 3
                            ).fill()
                        } else {
                            NSRect(
                                x: gutterWidth - markerBarWidth - 1,
                                y: lineRect.minY,
                                width: markerBarWidth,
                                height: lineRect.height
                            ).fill()
                        }
                    }
                }
            }

            lineNumber += 1
            let nextIndex = NSMaxRange(lineRange)
            if nextIndex <= charIndex { break }
            charIndex = nextIndex
        }
    }

    // MARK: - Scroll to line and highlight match

    func scrollToLineAndHighlight(lineNumber: Int, columnRange: Range<Int>) {
        let text = string as NSString
        guard text.length > 0 else { return }

        // Find the character range for the target line
        var currentLine = 1
        var lineStart = 0
        while currentLine < lineNumber && lineStart < text.length {
            let lineRange = text.lineRange(for: NSRange(location: lineStart, length: 0))
            lineStart = NSMaxRange(lineRange)
            currentLine += 1
        }

        guard currentLine == lineNumber else { return }

        let lineRange = text.lineRange(for: NSRange(location: lineStart, length: 0))

        // Calculate the match range within this line
        let matchLocation = lineStart + columnRange.lowerBound
        let matchLength = columnRange.upperBound - columnRange.lowerBound
        let matchRange = NSRange(
            location: min(matchLocation, text.length),
            length: min(matchLength, text.length - min(matchLocation, text.length))
        )

        // Select the match range and scroll to it
        setSelectedRange(matchRange)
        scrollRangeToVisible(lineRange)

        // Show native find indicator (yellow bounce, like CotEditor)
        if matchRange.length > 0 {
            showFindIndicator(for: matchRange)
        }
    }

    // MARK: - Click handling for gutter diff popover

    override func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)

        // Only intercept clicks in the gutter area
        guard localPoint.x < EditorTextViewConstants.gutterWidth else {
            super.mouseDown(with: event)
            return
        }

        guard let layoutManager, let textContainer else { return }

        let text = string as NSString
        guard text.length > 0 else { return }

        let containerOrigin = textContainerOrigin
        let textPoint = NSPoint(x: containerOrigin.x, y: localPoint.y - containerOrigin.y)

        let charIndex = layoutManager.characterIndex(
            for: textPoint, in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )

        let preText = text.substring(to: min(charIndex, text.length))
        let clickedLine = preText.components(separatedBy: "\n").count

        guard gutterDiff.markers[clickedLine] != nil else { return }

        guard let hunk = gutterDiff.hunks.first(where: { hunk in
            if hunk.kind == .deleted {
                return clickedLine == max(hunk.newStart, 1)
            } else {
                return clickedLine >= hunk.newStart && clickedLine < hunk.newStart + hunk.newCount
            }
        }) else { return }

        showDiffPopover(for: hunk, at: localPoint)
    }

    private func showDiffPopover(for hunk: GutterDiffHunk, at point: NSPoint) {
        let gutterWidth = EditorTextViewConstants.gutterWidth

        // Build line data for the popover text view
        let currentLines = string.components(separatedBy: "\n")
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

        // Create the HunkNSTextView-style popover
        let popoverWidth: CGFloat = 560
        let maxPopoverHeight: CGFloat = 250

        let popoverTextView = DiffPopoverTextView()
        popoverTextView.configure(lines: popoverLines, fileExtension: fileExtension, width: popoverWidth)

        // Get actual content height from layout manager after layout
        let contentHeight: CGFloat
        if let lm = popoverTextView.layoutManager, let tc = popoverTextView.textContainer {
            lm.ensureLayout(for: tc)
            let usedRect = lm.usedRect(for: tc)
            contentHeight = usedRect.height + DiffPopoverConstants.verticalPadding * 2
        } else {
            contentHeight = CGFloat(popoverLines.count) * 17 + DiffPopoverConstants.verticalPadding * 2
        }

        // Fit content but cap at max height
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
        popover.show(relativeTo: anchorRect, of: self, preferredEdge: .maxX)
    }
}

// MARK: - Diff Popover

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

/// Draws diff lines with line number gutter and colored backgrounds, like HunkNSTextView.
final class DiffPopoverTextView: NSTextView {
    private var lineData: [(kind: GitDiffLineKind, oldNum: Int?, newNum: Int?)] = []

    func configure(lines: [DiffPopoverLine], fileExtension: String, width: CGFloat) {
        let constants = DiffPopoverConstants.self

        appearance = NSApp.effectiveAppearance

        isEditable = false
        isSelectable = true
        isRichText = false
        font = constants.font
        backgroundColor = .windowBackgroundColor
        drawsBackground = true
        textColor = .labelColor
        textContainerInset = NSSize(width: constants.gutterWidth, height: constants.verticalPadding)

        // No line wrapping — horizontal scroll if needed
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

        // Gutter background
        NSColor.controlBackgroundColor.withAlphaComponent(0.3).setFill()
        NSRect(x: 0, y: rect.minY, width: gw, height: rect.height).fill()

        // Gutter separator
        NSColor.separatorColor.withAlphaComponent(0.15).setStroke()
        NSBezierPath.strokeLine(
            from: NSPoint(x: gw - 0.5, y: rect.minY),
            to: NSPoint(x: gw - 0.5, y: rect.maxY)
        )

        guard text.length > 0 else { return }

        let fullRange = layoutManager.glyphRange(forBoundingRect: rect, in: textContainer)
        let charRange = layoutManager.characterRange(forGlyphRange: fullRange, actualGlyphRange: nil)

        let lineNumAttrs: [NSAttributedString.Key: Any] = [
            .font: constants.lineNumFont,
            .foregroundColor: NSColor.secondaryLabelColor,
        ]

        let colWidth: CGFloat = (gw - 6) / 2  // tight two-column layout

        text.enumerateSubstrings(in: charRange, options: [.byLines, .substringNotRequired]) { _, substringRange, enclosingRange, _ in
            let lineIdx = self.lineIndex(forCharacterIndex: substringRange.location)
            guard lineIdx < self.lineData.count else { return }

            let glyphRange = layoutManager.glyphRange(forCharacterRange: enclosingRange, actualCharacterRange: nil)
            var lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            lineRect.origin.y += containerOrigin.y

            // Line background
            let data = self.lineData[lineIdx]
            let bgColor: NSColor = data.kind == .added
                ? .systemGreen.withAlphaComponent(0.12)
                : .systemRed.withAlphaComponent(0.12)
            var fullLineRect = lineRect
            fullLineRect.origin.x = gw
            fullLineRect.size.width = self.bounds.width - gw
            bgColor.setFill()
            fullLineRect.fill()

            let y = lineRect.minY

            // Old line number (right-aligned in left column)
            if let old = data.oldNum {
                let str = "\(old)" as NSString
                let size = str.size(withAttributes: lineNumAttrs)
                str.draw(at: NSPoint(x: colWidth - size.width, y: y), withAttributes: lineNumAttrs)
            }

            // New line number (right-aligned in right column)
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
