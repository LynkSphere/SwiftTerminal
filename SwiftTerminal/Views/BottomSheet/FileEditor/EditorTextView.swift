import AppKit

enum EditorTextViewConstants {
    static let gutterWidth: CGFloat = 48
    static let markerBarWidth: CGFloat = 3
    static let foldColumnWidth: CGFloat = 12

    // Diff mode gutter layout (single line number, no fold column)
    static let diffGutterWidth: CGFloat = 52
    static let diffNumEndX: CGFloat = 42
    static let diffMarkerX: CGFloat = 46
}

// MARK: - Editor Text View with Gutter

final class EditorTextView: NSTextView {
    var gutterDiff: GutterDiffResult = .empty
    var fileExtension: String = ""
    let foldingManager = FoldingManager()

    // Diff mode
    var diffLineKinds: [Int: GitDiffLineKind] = [:]
    var diffLineNumbers: [Int: GitDiffLineNumbers] = [:]
    var isDiffMode: Bool { !diffLineKinds.isEmpty }
    var diffGutterClickHandler: ((Int, NSPoint) -> Void)?

    var editorFontSize: CGFloat = 12
    var lineNumberFontSize: CGFloat = 11
    private var lineNumberFont: NSFont { NSFont.monospacedDigitSystemFont(ofSize: lineNumberFontSize, weight: .medium) }
    private let indentUnit = "    " // 4 spaces

    // MARK: - Current Line Highlight

    private var currentLineHighlightColor: NSColor {
        NSColor.labelColor.withAlphaComponent(0.06)
    }

    override func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
        super.setSelectedRange(charRange, affinity: affinity, stillSelecting: stillSelectingFlag)
        needsDisplay = true
    }

    private var currentCursorLine: Int {
        let text = string as NSString
        guard text.length > 0 else { return 1 }
        let loc = min(selectedRange().location, text.length)
        let pre = text.substring(to: loc)
        return pre.components(separatedBy: "\n").count
    }

    // MARK: - Bracket Matching

    private static let bracketPairs: [(open: Character, close: Character)] = [
        ("{", "}"), ("(", ")"), ("[", "]"),
    ]

    /// Returns the indices of the matched bracket pair near the cursor, if any.
    private func matchedBracketIndices() -> (Int, Int)? {
        let text = string
        let chars = Array(text.unicodeScalars)
        guard !chars.isEmpty else { return nil }
        let loc = selectedRange().location

        // Check character before cursor and at cursor
        for offset in [loc - 1, loc] {
            guard offset >= 0 && offset < chars.count else { continue }
            let c = Character(chars[offset])

            for pair in Self.bracketPairs {
                if c == pair.open {
                    if let match = Self.findMatchingClose(in: chars, from: offset, open: pair.open, close: pair.close) {
                        return (offset, match)
                    }
                } else if c == pair.close {
                    if let match = Self.findMatchingOpen(in: chars, from: offset, open: pair.open, close: pair.close) {
                        return (match, offset)
                    }
                }
            }
        }
        return nil
    }

    private static func findMatchingClose(in chars: [Unicode.Scalar], from: Int, open: Character, close: Character) -> Int? {
        var depth = 1
        let openScalar = open.unicodeScalars.first!
        let closeScalar = close.unicodeScalars.first!
        for i in (from + 1)..<chars.count {
            if chars[i] == openScalar { depth += 1 }
            else if chars[i] == closeScalar { depth -= 1; if depth == 0 { return i } }
        }
        return nil
    }

    private static func findMatchingOpen(in chars: [Unicode.Scalar], from: Int, open: Character, close: Character) -> Int? {
        var depth = 1
        let openScalar = open.unicodeScalars.first!
        let closeScalar = close.unicodeScalars.first!
        for i in stride(from: from - 1, through: 0, by: -1) {
            if chars[i] == closeScalar { depth += 1 }
            else if chars[i] == openScalar { depth -= 1; if depth == 0 { return i } }
        }
        return nil
    }

    private func drawBracketHighlights() {
        guard let layoutManager, let textContainer else { return }
        guard let (openIdx, closeIdx) = matchedBracketIndices() else { return }

        let containerOrigin = textContainerOrigin
        let highlightColor = NSColor.labelColor.withAlphaComponent(0.15)
        let borderColor = NSColor.labelColor.withAlphaComponent(0.3)

        for idx in [openIdx, closeIdx] {
            let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: idx, length: 1), actualCharacterRange: nil)
            guard glyphRange.location != NSNotFound else { continue }
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            rect.origin.x += containerOrigin.x
            rect.origin.y += containerOrigin.y
            let rounded = NSBezierPath(roundedRect: rect.insetBy(dx: -1, dy: 0), xRadius: 2, yRadius: 2)
            highlightColor.setFill()
            rounded.fill()
            borderColor.setStroke()
            rounded.lineWidth = 0.5
            rounded.stroke()
        }
    }

    // MARK: - Folding

    func recomputeFolding() {
        foldingManager.recompute(for: string)
    }

    private func toggleFold(at lineNumber: Int) {
        foldingManager.toggleFold(lineNumber)

        // Re-highlight to reset attributes, then re-apply fold hiding
        let source = string
        let ranges = selectedRanges
        let highlighted = SyntaxHighlighter.highlight(source, fileExtension: fileExtension, fontSize: editorFontSize)
        textStorage?.setAttributedString(highlighted)
        setSelectedRanges(ranges, affinity: .downstream, stillSelecting: false)
        applyFoldAttributes()
        needsDisplay = true
    }

    /// Applies hidden text attributes to all currently-folded regions.
    /// Call after syntax highlighting to layer fold hiding on top.
    func applyFoldAttributes() {
        guard let textStorage else { return }
        let text = string as NSString
        guard text.length > 0 else { return }

        let hiddenStyle = NSMutableParagraphStyle()
        hiddenStyle.maximumLineHeight = 0.001
        hiddenStyle.minimumLineHeight = 0.001
        hiddenStyle.lineSpacing = 0
        hiddenStyle.paragraphSpacing = 0
        hiddenStyle.paragraphSpacingBefore = 0

        let hiddenAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 0.001, weight: .regular),
            .foregroundColor: NSColor.clear,
            .paragraphStyle: hiddenStyle,
        ]

        for startLine in foldingManager.foldedStartLines {
            guard let region = foldingManager.region(startingAt: startLine) else { continue }
            let hideFromLine = region.startLine + 1
            guard hideFromLine <= region.endLine else { continue }
            guard region.startLine < foldingManager.lineStarts.count else { continue }

            let startIdx = foldingManager.lineStarts[region.startLine] // start of hideFromLine
            let endIdx = region.endLine < foldingManager.lineStarts.count
                ? foldingManager.lineStarts[region.endLine]
                : text.length
            let range = NSRange(location: startIdx, length: endIdx - startIdx)
            guard range.length > 0, NSMaxRange(range) <= text.length else { continue }

            textStorage.addAttributes(hiddenAttrs, range: range)
        }
    }

    // MARK: - Auto-Close Pairs

    private static let autoClosePairs: [Character: Character] = [
        "{": "}", "(": ")", "[": "]", "\"": "\"", "'": "'",
    ]
    private static let openBrackets: Set<Character> = ["{", "(", "["]
    private static let closeBrackets: Set<Character> = ["}", ")", "]"]

    private func charAt(_ index: Int) -> Character? {
        let text = string as NSString
        guard index >= 0, index < text.length else { return nil }
        let uni = text.character(at: index)
        return Character(UnicodeScalar(uni)!)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        guard let str = string as? String, str.count == 1, let char = str.first else {
            super.insertText(string, replacementRange: replacementRange)
            return
        }

        let loc = selectedRange().location

        // Typing a closing bracket or quote that already exists right after cursor — skip over it
        if (Self.closeBrackets.contains(char) || char == "\"" || char == "'"),
           let nextChar = charAt(loc), nextChar == char {
            setSelectedRange(NSRange(location: loc + 1, length: 0))
            return
        }

        // Auto-close opening brackets
        if Self.openBrackets.contains(char), let closer = Self.autoClosePairs[char] {
            super.insertText(string, replacementRange: replacementRange)
            let afterLoc = selectedRange().location
            super.insertText(String(closer), replacementRange: NSRange(location: afterLoc, length: 0))
            setSelectedRange(NSRange(location: afterLoc, length: 0))
            return
        }

        // Auto-close quotes (only if not preceded by alphanumeric, suggesting end of word)
        if (char == "\"" || char == "'"), let closer = Self.autoClosePairs[char] {
            let shouldAutoClose: Bool
            if let prevChar = charAt(loc - 1) {
                shouldAutoClose = !prevChar.isLetter && !prevChar.isNumber
            } else {
                shouldAutoClose = true
            }

            if shouldAutoClose {
                super.insertText(string, replacementRange: replacementRange)
                let afterLoc = selectedRange().location
                super.insertText(String(closer), replacementRange: NSRange(location: afterLoc, length: 0))
                setSelectedRange(NSRange(location: afterLoc, length: 0))
                return
            }
        }

        super.insertText(string, replacementRange: replacementRange)
    }

    override func deleteBackward(_ sender: Any?) {
        let loc = selectedRange().location
        // Delete both characters of an empty auto-close pair
        if let prev = charAt(loc - 1), let next = charAt(loc),
           let closer = Self.autoClosePairs[prev], closer == next {
            super.deleteBackward(sender)
            deleteForward(sender)
            return
        }

        super.deleteBackward(sender)
    }

    // MARK: - Smart Editing

    override func insertNewline(_ sender: Any?) {
        let text = string as NSString
        let loc = selectedRange().location

        // Find current line and its leading whitespace
        let lineRange = text.lineRange(for: NSRange(location: loc, length: 0))
        let line = text.substring(with: lineRange)
        let leadingWhitespace = String(line.prefix(while: { $0 == " " || $0 == "\t" }))

        // Check if the character before the cursor is an opening brace
        let trimmed = text.substring(with: NSRange(location: lineRange.location, length: loc - lineRange.location))
            .trimmingCharacters(in: .whitespaces)
        let opensBlock = trimmed.hasSuffix("{")
        let extraIndent = opensBlock ? indentUnit : ""

        // Special case: cursor between {} — expand to three lines
        if opensBlock, let nextChar = charAt(loc), nextChar == "}" {
            super.insertNewline(sender)
            let indentedLine = leadingWhitespace + indentUnit
            let closingLine = "\n" + leadingWhitespace
            insertText(indentedLine + closingLine, replacementRange: selectedRange())
            // Place cursor at end of indented line
            let cursorLoc = selectedRange().location - closingLine.count
            setSelectedRange(NSRange(location: cursorLoc, length: 0))
            return
        }

        super.insertNewline(sender)
        insertText(leadingWhitespace + extraIndent, replacementRange: selectedRange())
    }

    override func insertTab(_ sender: Any?) {
        let range = selectedRange()
        guard range.length > 0 else {
            insertText(indentUnit, replacementRange: range)
            return
        }
        indentSelection(indent: true)
    }

    override func insertBacktab(_ sender: Any?) {
        indentSelection(indent: false)
    }

    private func indentSelection(indent: Bool) {
        let text = string as NSString
        let range = selectedRange()
        let hadSelection = range.length > 0
        let lineRange = text.lineRange(for: range)
        let linesStr = text.substring(with: lineRange)
        let lines = linesStr.components(separatedBy: "\n")

        var newLines: [String] = []
        var firstLineDelta = 0
        for (i, line) in lines.enumerated() {
            // Skip the trailing empty component from lineRange
            if i == lines.count - 1 && line.isEmpty {
                newLines.append(line)
                continue
            }
            if indent {
                newLines.append(indentUnit + line)
                if i == 0 { firstLineDelta = indentUnit.count }
            } else {
                // Remove up to one indent unit from the start
                var removed = 0
                var start = line.startIndex
                while removed < indentUnit.count, start < line.endIndex, line[start] == " " {
                    start = line.index(after: start)
                    removed += 1
                }
                newLines.append(String(line[start...]))
                if i == 0 { firstLineDelta = -removed }
            }
        }

        let replacement = newLines.joined(separator: "\n")
        if shouldChangeText(in: lineRange, replacementString: replacement) {
            replaceCharacters(in: lineRange, with: replacement)
            didChangeText()
            if hadSelection {
                setSelectedRange(NSRange(location: lineRange.location, length: (replacement as NSString).length))
            } else {
                let newLoc = max(lineRange.location, range.location + firstLineDelta)
                setSelectedRange(NSRange(location: newLoc, length: 0))
            }
        }
    }

    // MARK: - Comment Toggle (Cmd+/)

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "/" {
            toggleComment()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private var commentPrefix: String {
        switch fileExtension {
        case "py", "rb", "sh", "bash", "zsh", "yml", "yaml", "toml":
            return "#"
        case "html", "xml", "svg":
            return "//" // simplified — full HTML comments are block-level
        default:
            return "//"
        }
    }

    private func toggleComment() {
        let text = string as NSString
        let range = selectedRange()
        let hadSelection = range.length > 0
        let lineRange = text.lineRange(for: range)
        let linesStr = text.substring(with: lineRange)
        let lines = linesStr.components(separatedBy: "\n")
        let prefix = commentPrefix + " "

        // Determine if we're commenting or uncommenting:
        // If all non-empty lines are commented, uncomment. Otherwise, comment.
        let nonEmptyLines = lines.enumerated().filter { i, line in
            !(i == lines.count - 1 && line.isEmpty) && !line.trimmingCharacters(in: .whitespaces).isEmpty
        }
        let allCommented = nonEmptyLines.allSatisfy { $0.1.trimmingCharacters(in: .init(charactersIn: " \t")).hasPrefix(prefix.trimmingCharacters(in: .whitespaces)) }

        var newLines: [String] = []
        var firstLineDelta = 0
        for (i, line) in lines.enumerated() {
            if i == lines.count - 1 && line.isEmpty {
                newLines.append(line)
                continue
            }
            if allCommented {
                // Remove comment prefix (handle both "// " and "//")
                let trimPrefix = commentPrefix
                if let r = line.range(of: trimPrefix + " ") {
                    var modified = line
                    let removedCount = line.distance(from: r.lowerBound, to: r.upperBound)
                    modified.removeSubrange(r)
                    newLines.append(modified)
                    if i == 0 { firstLineDelta = -removedCount }
                } else if let r = line.range(of: trimPrefix) {
                    var modified = line
                    let removedCount = line.distance(from: r.lowerBound, to: r.upperBound)
                    modified.removeSubrange(r)
                    newLines.append(modified)
                    if i == 0 { firstLineDelta = -removedCount }
                } else {
                    newLines.append(line)
                }
            } else {
                if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    newLines.append(line)
                } else {
                    // Insert comment at the first non-whitespace position
                    let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
                    let rest = String(line.dropFirst(indent.count))
                    newLines.append(indent + prefix + rest)
                    if i == 0 { firstLineDelta = prefix.count }
                }
            }
        }

        let replacement = newLines.joined(separator: "\n")
        if shouldChangeText(in: lineRange, replacementString: replacement) {
            replaceCharacters(in: lineRange, with: replacement)
            didChangeText()
            if hadSelection {
                setSelectedRange(NSRange(location: lineRange.location, length: (replacement as NSString).length))
            } else {
                let newLoc = max(lineRange.location, range.location + firstLineDelta)
                setSelectedRange(NSRange(location: newLoc, length: 0))
            }
        }
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)

        guard let layoutManager, let textContainer else { return }

        if isDiffMode {
            drawDiffBackground(in: rect, layoutManager: layoutManager, textContainer: textContainer)
        } else {
            drawEditorBackground(in: rect, layoutManager: layoutManager, textContainer: textContainer)
        }
    }

    // MARK: - Diff Mode Background

    private func drawDiffBackground(in rect: NSRect, layoutManager: NSLayoutManager, textContainer: NSTextContainer) {
        let constants = EditorTextViewConstants.self
        let containerOrigin = textContainerOrigin
        let text = string as NSString
        guard text.length > 0 else { return }

        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: rect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        let lineNumAttrs: [NSAttributedString.Key: Any] = [
            .font: lineNumberFont,
            .foregroundColor: NSColor.secondaryLabelColor,
        ]

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

                let isVisible = lineRect.height > 1
                    && lineRect.minY + lineRect.height >= rect.minY && lineRect.minY <= rect.maxY

                if isVisible {
                    let lineKind = diffLineKinds[lineNumber]
                    let lineNums = diffLineNumbers[lineNumber]

                    // Draw line background for changed lines
                    if let kind = lineKind {
                        let bgColor = kind.color.withAlphaComponent(0.12)
                        var bgRect = lineRect
                        bgRect.origin.x = constants.diffGutterWidth
                        bgRect.size.width = max(bounds.width, enclosingScrollView?.contentSize.width ?? bounds.width) - constants.diffGutterWidth
                        bgColor.setFill()
                        bgRect.fill()

                        // Also tint the gutter area
                        let gutterBg = kind.color.withAlphaComponent(0.06)
                        gutterBg.setFill()
                        NSRect(x: 0, y: lineRect.minY, width: constants.diffGutterWidth, height: lineRect.height).fill()
                    }

                    let yCenter = lineRect.minY + (lineRect.height - ("0" as NSString).size(withAttributes: lineNumAttrs).height) / 2

                    // Single line number: prefer new, fall back to old (for removed lines)
                    let lineNum = lineNums?.new ?? lineNums?.old
                    if let num = lineNum {
                        let str = "\(num)" as NSString
                        let size = str.size(withAttributes: lineNumAttrs)
                        str.draw(at: NSPoint(x: constants.diffNumEndX - size.width, y: yCenter), withAttributes: lineNumAttrs)
                    }

                    // Draw marker bar for changed lines
                    if let kind = lineKind {
                        kind.color.setFill()
                        NSRect(x: constants.diffMarkerX, y: lineRect.minY, width: 3, height: lineRect.height).fill()
                    }
                }
            }

            lineNumber += 1
            let nextIndex = NSMaxRange(lineRange)
            if nextIndex <= charIndex { break }
            charIndex = nextIndex
        }
    }

    // MARK: - Editor Mode Background

    private func drawEditorBackground(in rect: NSRect, layoutManager: NSLayoutManager, textContainer: NSTextContainer) {
        let gutterWidth = EditorTextViewConstants.gutterWidth
        let markerBarWidth = EditorTextViewConstants.markerBarWidth
        let foldColWidth = EditorTextViewConstants.foldColumnWidth
        let containerOrigin = textContainerOrigin
        let text = string as NSString

        guard text.length > 0 else { return }

        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: rect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        let lineNumAttrs: [NSAttributedString.Key: Any] = [
            .font: lineNumberFont,
            .foregroundColor: NSColor.secondaryLabelColor,
        ]

        let foldBadgeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]

        // Count lines before visible range
        var startLineNumber = 1
        if visibleCharRange.location > 0 {
            let preText = text.substring(to: visibleCharRange.location)
            startLineNumber = preText.components(separatedBy: "\n").count
        }

        let lineNumEndX = gutterWidth - foldColWidth - markerBarWidth - 6
        let markerBarX = gutterWidth - foldColWidth - markerBarWidth - 1
        let foldCenterX = gutterWidth - foldColWidth / 2

        let cursorLine = currentCursorLine

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

                let isHidden = foldingManager.isLineHidden(lineNumber)
                let isVisible = !isHidden && lineRect.height > 1
                    && lineRect.minY + lineRect.height >= rect.minY && lineRect.minY <= rect.maxY

                if isVisible {
                    // Draw current line highlight
                    if lineNumber == cursorLine {
                        currentLineHighlightColor.setFill()
                        NSRect(x: 0, y: lineRect.minY, width: bounds.width, height: lineRect.height).fill()
                    }

                    // Draw line number right-aligned
                    let numStr = "\(lineNumber)" as NSString
                    let size = numStr.size(withAttributes: lineNumAttrs)
                    let x = lineNumEndX - size.width
                    let y = lineRect.minY + (lineRect.height - size.height) / 2
                    numStr.draw(at: NSPoint(x: x, y: y), withAttributes: lineNumAttrs)

                    // Draw git change marker bar
                    if let kind = gutterDiff.markers[lineNumber] {
                        kind.color.setFill()
                        if kind == .deleted {
                            NSRect(x: markerBarX, y: lineRect.minY - 1, width: markerBarWidth + 1, height: 3).fill()
                        } else {
                            NSRect(x: markerBarX, y: lineRect.minY, width: markerBarWidth, height: lineRect.height).fill()
                        }
                    }

                    // Draw fold indicator
                    if foldingManager.isFoldable(lineNumber) {
                        let isFolded = foldingManager.isFolded(lineNumber)
                        let cy = lineRect.minY + lineRect.height / 2

                        let triangle = NSBezierPath()
                        if isFolded {
                            // ▶ pointing right
                            triangle.move(to: NSPoint(x: foldCenterX - 2.5, y: cy - 4))
                            triangle.line(to: NSPoint(x: foldCenterX - 2.5, y: cy + 4))
                            triangle.line(to: NSPoint(x: foldCenterX + 3, y: cy))
                        } else {
                            // ▼ pointing down
                            triangle.move(to: NSPoint(x: foldCenterX - 4, y: cy - 2.5))
                            triangle.line(to: NSPoint(x: foldCenterX + 4, y: cy - 2.5))
                            triangle.line(to: NSPoint(x: foldCenterX, y: cy + 3))
                        }
                        triangle.close()
                        NSColor.tertiaryLabelColor.setFill()
                        triangle.fill()

                        // Draw fold badge "⋯" when folded
                        if isFolded {
                            let badgeText = " ⋯ " as NSString
                            let usedRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
                            let badgeSize = badgeText.size(withAttributes: foldBadgeAttrs)
                            let badgeX = containerOrigin.x + usedRect.maxX + 2
                            let badgeY = lineRect.minY + (lineRect.height - badgeSize.height) / 2

                            let badgeRect = NSRect(
                                x: badgeX, y: badgeY - 1,
                                width: badgeSize.width + 4, height: badgeSize.height + 2
                            )
                            NSColor.separatorColor.withAlphaComponent(0.15).setFill()
                            NSBezierPath(roundedRect: badgeRect, xRadius: 3, yRadius: 3).fill()
                            NSColor.separatorColor.withAlphaComponent(0.4).setStroke()
                            NSBezierPath(roundedRect: badgeRect, xRadius: 3, yRadius: 3).stroke()
                            badgeText.draw(at: NSPoint(x: badgeX + 2, y: badgeY), withAttributes: foldBadgeAttrs)
                        }
                    }
                }
            }

            lineNumber += 1
            let nextIndex = NSMaxRange(lineRange)
            if nextIndex <= charIndex { break }
            charIndex = nextIndex
        }

        // Draw bracket matching highlights on top
        drawBracketHighlights()
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

    // MARK: - Scroll to line

    func scrollToLine(_ lineNumber: Int) {
        let text = string as NSString
        guard text.length > 0 else { return }
        var currentLine = 1
        var lineStart = 0
        while currentLine < lineNumber && lineStart < text.length {
            let lineRange = text.lineRange(for: NSRange(location: lineStart, length: 0))
            lineStart = NSMaxRange(lineRange)
            currentLine += 1
        }
        let lineRange = text.lineRange(for: NSRange(location: lineStart, length: 0))
        scrollRangeToVisible(lineRange)
    }

    override func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)

        // Diff mode gutter click
        if isDiffMode {
            guard localPoint.x < EditorTextViewConstants.diffGutterWidth else {
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
            diffGutterClickHandler?(clickedLine, localPoint)
            return
        }

        let gutterWidth = EditorTextViewConstants.gutterWidth
        let foldColStart = gutterWidth - EditorTextViewConstants.foldColumnWidth

        // Only intercept clicks in the gutter area
        guard localPoint.x < gutterWidth else {
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

        // Fold indicator click
        if localPoint.x >= foldColStart && foldingManager.isFoldable(clickedLine) {
            toggleFold(at: clickedLine)
            return
        }

        // Diff popover click
        guard gutterDiff.markers[clickedLine] != nil else { return }

        guard let hunk = gutterDiff.hunks.first(where: { hunk in
            if hunk.kind == .deleted {
                return clickedLine == max(hunk.newStart, 1)
            } else {
                return clickedLine >= hunk.newStart && clickedLine < hunk.newStart + hunk.newCount
            }
        }) else { return }

        DiffPopoverPresenter.showDiffPopover(for: hunk, at: localPoint, in: self)
    }
}
