import AppKit
import SwiftUI

struct FileEditorPanel: View {
    let fileURL: URL
    let directoryURL: URL
    @Environment(EditorPanel.self) private var panel
    @State private var content: String = ""
    @State private var savedContent: String = ""
    @State private var isLoaded = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var gutterDiff: GutterDiffResult = .empty

    private var hasUnsavedChanges: Bool {
        isLoaded && content != savedContent
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if isLoaded {
                HighlightedTextEditor(
                    text: $content,
                    fileExtension: fileURL.pathExtension.lowercased(),
                    gutterDiff: gutterDiff
                )
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Cannot Open File", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: fileURL) { loadFile() }
        .onChange(of: hasUnsavedChanges) { _, dirty in
            panel.isDirty = dirty
        }
        .alert("Unsaved Changes", isPresented: Binding(
            get: { panel.showUnsavedAlert },
            set: { if !$0 { panel.cancelDiscard() } }
        )) {
            Button("Save") {
                saveFile()
                panel.confirmDiscard()
            }
            Button("Discard", role: .destructive) {
                panel.confirmDiscard()
            }
            Button("Cancel", role: .cancel) {
                panel.cancelDiscard()
            }
        } message: {
            Text("Do you want to save changes to \"\(fileURL.lastPathComponent)\"?")
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(nsImage: fileURL.fileIcon)
                .resizable()
                .frame(width: 16, height: 16)
            Text(fileURL.relativePath(from: directoryURL))
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)

            if hasUnsavedChanges {
                Circle()
                    .fill(.secondary)
                    .frame(width: 6, height: 6)
                    .help("Unsaved changes")
            }

            Spacer()

            if isSaving {
                ProgressView()
                    .controlSize(.small)
            }

            Button { saveFile() } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!hasUnsavedChanges || isSaving)
            .help("Save")

            Button { panel.close() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Close")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func loadFile() {
        content = ""
        savedContent = ""
        isLoaded = false
        errorMessage = nil
        gutterDiff = .empty
        panel.isDirty = false
        do {
            let data = try Data(contentsOf: fileURL)
            guard let string = String(data: data, encoding: .utf8) else {
                errorMessage = "Binary file — cannot display."
                return
            }
            content = string
            savedContent = string
            isLoaded = true
            loadGutterDiff()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveFile() {
        isSaving = true
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            savedContent = content
            loadGutterDiff()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    private func loadGutterDiff() {
        Task {
            do {
                gutterDiff = try await GitRepository.shared.gutterDiff(for: fileURL, in: directoryURL)
            } catch {
                gutterDiff = .empty
            }
        }
    }
}

// MARK: - NSTextView wrapper with syntax highlighting

struct HighlightedTextEditor: NSViewRepresentable {
    @Binding var text: String
    let fileExtension: String
    var gutterDiff: GutterDiffResult

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator

        // Set up ruler view for line numbers and git markers
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        let rulerView = LineNumberRulerView(textView: textView, scrollView: scrollView)
        rulerView.update(gutterDiff: gutterDiff)
        scrollView.verticalRulerView = rulerView

        context.coordinator.textView = textView
        context.coordinator.rulerView = rulerView

        // Observe bounds changes to redraw ruler on scroll
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.boundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        // Initial content
        let highlighted = SyntaxHighlighter.highlight(text, fileExtension: fileExtension)
        textView.textStorage?.setAttributedString(highlighted)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Update gutter diff on ruler
        if let rulerView = scrollView.verticalRulerView as? LineNumberRulerView {
            rulerView.update(gutterDiff: gutterDiff)
        }

        // Only update if the binding changed externally (not from editing)
        if !context.coordinator.isEditing, textView.string != text {
            let highlighted = SyntaxHighlighter.highlight(text, fileExtension: fileExtension)
            textView.textStorage?.setAttributedString(highlighted)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: HighlightedTextEditor
        weak var textView: NSTextView?
        weak var rulerView: LineNumberRulerView?
        var isEditing = false
        private var rehighlightTask: DispatchWorkItem?

        init(_ parent: HighlightedTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            isEditing = true
            parent.text = textView.string
            isEditing = false

            // Refresh ruler on text change
            rulerView?.needsDisplay = true

            // Debounced re-highlight
            rehighlightTask?.cancel()
            let task = DispatchWorkItem { [weak self] in
                guard let self, let tv = self.textView else { return }
                let source = tv.string
                let ext = self.parent.fileExtension
                let selectedRanges = tv.selectedRanges
                let highlighted = SyntaxHighlighter.highlight(source, fileExtension: ext)
                tv.textStorage?.setAttributedString(highlighted)
                tv.setSelectedRanges(selectedRanges, affinity: .downstream, stillSelecting: false)
            }
            rehighlightTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
        }

        @objc func boundsDidChange(_ notification: Notification) {
            rulerView?.needsDisplay = true
        }
    }
}

// MARK: - Line Number Ruler View

final class LineNumberRulerView: NSRulerView {
    private var gutterDiff: GutterDiffResult = .empty
    private weak var textView: NSTextView?

    private let lineNumberFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private let markerWidth: CGFloat = 3

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        self.ruleThickness = 44
        self.clientView = textView
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(gutterDiff: GutterDiffResult) {
        self.gutterDiff = gutterDiff
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        // Draw background
        NSColor.controlBackgroundColor.withAlphaComponent(0.3).setFill()
        rect.fill()

        // Draw separator line on the right edge
        NSColor.separatorColor.setStroke()
        let sepPath = NSBezierPath()
        sepPath.move(to: NSPoint(x: ruleThickness - 0.5, y: rect.minY))
        sepPath.line(to: NSPoint(x: ruleThickness - 0.5, y: rect.maxY))
        sepPath.lineWidth = 0.5
        sepPath.stroke()

        let text = textView.string as NSString
        guard text.length > 0 else { return }

        let visibleRect = scrollView?.contentView.bounds ?? .zero
        let containerOrigin = textView.textContainerOrigin

        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: lineNumberFont,
            .foregroundColor: NSColor.secondaryLabelColor,
        ]

        // Count lines before the visible range to find the starting line number
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

                // Convert from textView coordinates to ruler coordinates
                let yInRuler = lineRect.minY - visibleRect.origin.y

                if yInRuler + lineRect.height >= rect.minY && yInRuler <= rect.maxY {
                    // Draw line number right-aligned
                    let numStr = "\(lineNumber)" as NSString
                    let size = numStr.size(withAttributes: attrs)
                    let x = ruleThickness - markerWidth - size.width - 6
                    let y = yInRuler + (lineRect.height - size.height) / 2
                    numStr.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)

                    // Draw git change marker bar
                    if let kind = gutterDiff.markers[lineNumber] {
                        kind.color.setFill()
                        if kind == .deleted {
                            // Deleted: thin horizontal bar to indicate removed lines
                            NSRect(
                                x: ruleThickness - markerWidth - 1,
                                y: yInRuler - 1,
                                width: markerWidth + 1,
                                height: 3
                            ).fill()
                        } else {
                            // Added/modified: vertical bar spanning the line height
                            NSRect(
                                x: ruleThickness - markerWidth - 1,
                                y: yInRuler,
                                width: markerWidth,
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

    // MARK: - Click handling for diff popover

    override func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)

        // Only handle clicks near the marker area (right side of gutter)
        guard localPoint.x >= ruleThickness - 16 else {
            super.mouseDown(with: event)
            return
        }

        guard let textView, let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let text = textView.string as NSString
        guard text.length > 0 else { return }

        let visibleRect = scrollView?.contentView.bounds ?? .zero
        let containerOrigin = textView.textContainerOrigin

        // Convert click point to text view coordinates
        let textViewY = localPoint.y + visibleRect.origin.y - containerOrigin.y
        let textViewPoint = NSPoint(x: 0, y: textViewY)

        let charIndex = layoutManager.characterIndex(
            for: textViewPoint, in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )

        // Count line number at that character
        let preText = text.substring(to: min(charIndex, text.length))
        let clickedLine = preText.components(separatedBy: "\n").count

        // Check if this line has a marker
        guard gutterDiff.markers[clickedLine] != nil else {
            super.mouseDown(with: event)
            return
        }

        // Find the hunk that contains this line
        guard let hunk = gutterDiff.hunks.first(where: { hunk in
            if hunk.kind == .deleted {
                return clickedLine == max(hunk.newStart, 1)
            } else {
                return clickedLine >= hunk.newStart && clickedLine < hunk.newStart + hunk.newCount
            }
        }) else {
            super.mouseDown(with: event)
            return
        }

        showDiffPopover(for: hunk, at: localPoint)
    }

    private func showDiffPopover(for hunk: GutterDiffHunk, at point: NSPoint) {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true

        let viewController = NSViewController()
        let container = NSView()

        // Title label
        let titleLabel = NSTextField(labelWithString: hunkTitle(for: hunk))
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // Diff text view
        let scrollView = NSTextView.scrollableTextView()
        let diffTextView = scrollView.documentView as! NSTextView
        diffTextView.isEditable = false
        diffTextView.isSelectable = true
        diffTextView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        diffTextView.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.5)
        diffTextView.textContainerInset = NSSize(width: 6, height: 4)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        // Build attributed string for diff content
        let diffString = buildDiffAttributedString(for: hunk)
        diffTextView.textStorage?.setAttributedString(diffString)

        container.addSubview(titleLabel)
        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),

            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        viewController.view = container
        let lineCount = max(hunk.oldContent.components(separatedBy: "\n").count, 1)
        let height = min(CGFloat(lineCount) * 16 + 44, 300)
        viewController.preferredContentSize = NSSize(width: 400, height: height)

        popover.contentViewController = viewController

        let anchorRect = NSRect(x: ruleThickness - 4, y: point.y - 4, width: 4, height: 8)
        popover.show(relativeTo: anchorRect, of: self, preferredEdge: .maxX)
    }

    private func hunkTitle(for hunk: GutterDiffHunk) -> String {
        switch hunk.kind {
        case .added:
            return "Added \(hunk.newCount) line\(hunk.newCount == 1 ? "" : "s")"
        case .modified:
            return "Modified \(hunk.newCount) line\(hunk.newCount == 1 ? "" : "s")"
        case .deleted:
            return "Deleted \(hunk.oldCount) line\(hunk.oldCount == 1 ? "" : "s")"
        }
    }

    private func buildDiffAttributedString(for hunk: GutterDiffHunk) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let baseFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

        let removedBg = NSColor.systemRed.withAlphaComponent(0.15)
        let addedBg = NSColor.systemGreen.withAlphaComponent(0.15)

        // Show old (removed) content
        if !hunk.oldContent.isEmpty {
            let oldLines = hunk.oldContent.components(separatedBy: "\n")
            for line in oldLines {
                let lineStr = NSMutableAttributedString(
                    string: "- " + line + "\n",
                    attributes: [
                        .font: baseFont,
                        .foregroundColor: NSColor.systemRed,
                        .backgroundColor: removedBg,
                    ]
                )
                result.append(lineStr)
            }
        }

        // For added-only hunks, show a summary
        if hunk.kind == .added {
            let addedStr = NSMutableAttributedString(
                string: "+ \(hunk.newCount) new line\(hunk.newCount == 1 ? "" : "s")\n",
                attributes: [
                    .font: baseFont,
                    .foregroundColor: NSColor.systemGreen,
                    .backgroundColor: addedBg,
                ]
            )
            result.append(addedStr)
        }

        return result
    }
}
