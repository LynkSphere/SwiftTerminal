import AppKit
import SwiftUI

struct HighlightedTextEditor: NSViewRepresentable {
    @Binding var text: String
    let fileExtension: String
    var gutterDiff: GutterDiffResult
    var highlightRequest: HighlightRequest?
    @Environment(\.editorFontSize) private var fontSize

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.autoresizesSubviews = true

        let minimapWidth: CGFloat = 16
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.autoresizingMask = [.width, .height]

        let contentSize = scrollView.contentSize
        let textContainer = NSTextContainer(containerSize: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = false

        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)

        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)

        let textView = EditorTextView(frame: NSRect(origin: .zero, size: contentSize), textContainer: textContainer)
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
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.editorFontSize = fontSize
        textView.lineNumberFontSize = fontSize - 1
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: EditorTextViewConstants.gutterWidth, height: 4)
        textView.delegate = context.coordinator

        // No line wrapping — horizontal scroll
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = []

        scrollView.documentView = textView

        textView.gutterDiff = gutterDiff
        textView.fileExtension = fileExtension
        context.coordinator.textView = textView

        // Minimap
        let minimap = EditorMinimap()
        minimap.autoresizingMask = [.minXMargin, .height]
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
        context.coordinator.minimapWidth = minimapWidth

        // Layout: scroll view fills container minus minimap width, minimap on right
        container.addSubview(scrollView)
        container.addSubview(minimap)
        context.coordinator.scrollView = scrollView

        // Observe scroll to update minimap viewport
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator, selector: #selector(Coordinator.scrollDidChange(_:)),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView
        )

        // Initial content + fold computation
        let highlighted = SyntaxHighlighter.highlight(text, fileExtension: fileExtension, fontSize: fontSize)
        textView.textStorage?.setAttributedString(highlighted)
        textView.recomputeFolding()

        // Apply highlight request after initial content is set
        if let request = highlightRequest {
            context.coordinator.lastAppliedHighlight = request
            DispatchQueue.main.async {
                textView.scrollToLineAndHighlight(
                    lineNumber: request.lineNumber,
                    columnRange: request.columnRange
                )
            }
        }

        // Ensure scroll starts at x=0 so the gutter is visible
        DispatchQueue.main.async {
            scrollView.contentView.setBoundsOrigin(
                NSPoint(x: 0, y: scrollView.contentView.bounds.origin.y)
            )
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

        textView.gutterDiff = gutterDiff
        textView.needsDisplay = true

        // Update minimap markers
        context.coordinator.updateMinimapMarkers(gutterDiff: gutterDiff, text: textView.string)

        // Only update if the binding changed externally (not from editing)
        if !context.coordinator.isEditing, textView.string != text {
            let highlighted = SyntaxHighlighter.highlight(text, fileExtension: fileExtension, fontSize: fontSize)
            textView.textStorage?.setAttributedString(highlighted)
            textView.recomputeFolding()
            textView.applyFoldAttributes()
        }

        // Apply pending highlight request
        if let request = highlightRequest, request != context.coordinator.lastAppliedHighlight {
            context.coordinator.lastAppliedHighlight = request
            DispatchQueue.main.async {
                textView.scrollToLineAndHighlight(
                    lineNumber: request.lineNumber,
                    columnRange: request.columnRange
                )
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: HighlightedTextEditor
        weak var textView: EditorTextView?
        weak var scrollView: NSScrollView?
        weak var minimap: EditorMinimap?
        var minimapWidth: CGFloat = 16
        var isEditing = false
        var lastAppliedHighlight: HighlightRequest?
        private var rehighlightTask: DispatchWorkItem?

        init(_ parent: HighlightedTextEditor) { self.parent = parent }

        @objc func scrollDidChange(_ notification: Notification) {
            guard let scrollView else { return }
            minimap?.updateViewport(from: scrollView)
        }

        func updateMinimapMarkers(gutterDiff: GutterDiffResult, text: String) {
            guard let minimap else { return }
            let lineCount = max(text.components(separatedBy: "\n").count, 1)
            minimap.totalLines = lineCount
            let colors: [Int: NSColor] = gutterDiff.markers.mapValues { $0.color }
            minimap.setMarkers(colors)
            if let scrollView {
                minimap.updateViewport(from: scrollView)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            isEditing = true
            parent.text = textView.string
            isEditing = false

            // Debounced re-highlight and fold recomputation
            rehighlightTask?.cancel()
            let task = DispatchWorkItem { [weak self] in
                guard let self, let tv = self.textView else { return }
                let source = tv.string
                let ext = self.parent.fileExtension
                let selectedRanges = tv.selectedRanges
                let highlighted = SyntaxHighlighter.highlight(source, fileExtension: ext, fontSize: tv.editorFontSize)
                tv.textStorage?.setAttributedString(highlighted)
                tv.setSelectedRanges(selectedRanges, affinity: .downstream, stillSelecting: false)
                tv.recomputeFolding()
                tv.applyFoldAttributes()
            }
            rehighlightTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
        }
    }
}
