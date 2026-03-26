import AppKit
import SwiftUI

struct HighlightedTextEditor: NSViewRepresentable {
    @Binding var text: String
    let fileExtension: String
    var gutterDiff: GutterDiffResult
    var highlightRequest: HighlightRequest?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

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
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
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

        // Initial content
        let highlighted = SyntaxHighlighter.highlight(text, fileExtension: fileExtension)
        textView.textStorage?.setAttributedString(highlighted)

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

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? EditorTextView else { return }

        textView.gutterDiff = gutterDiff
        textView.needsDisplay = true

        // Only update if the binding changed externally (not from editing)
        if !context.coordinator.isEditing, textView.string != text {
            let highlighted = SyntaxHighlighter.highlight(text, fileExtension: fileExtension)
            textView.textStorage?.setAttributedString(highlighted)
        }

        // Apply pending highlight request
        if let request = highlightRequest, request != context.coordinator.lastAppliedHighlight {
            context.coordinator.lastAppliedHighlight = request
            // Delay slightly to ensure layout is complete after content load
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
        var isEditing = false
        var lastAppliedHighlight: HighlightRequest?
        private var rehighlightTask: DispatchWorkItem?

        init(_ parent: HighlightedTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            isEditing = true
            parent.text = textView.string
            isEditing = false

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
    }
}
