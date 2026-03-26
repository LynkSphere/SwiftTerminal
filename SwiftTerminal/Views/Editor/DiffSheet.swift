import AppKit
import SwiftUI

struct DiffPanel: View {
    let reference: GitDiffReference
    @Environment(EditorPanel.self) private var panel
    @State private var presentation: DiffFilePresentation?
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            header

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = presentation?.message, presentation?.hunks.isEmpty == true {
                ContentUnavailableView {
                    Text(message)
                        .foregroundStyle(.secondary)
                }
            } else if let presentation {
                DiffHunkListView(
                    hunks: presentation.hunks,
                    reference: reference,
                    fileExtension: reference.fileURL.pathExtension.lowercased(),
                    onReload: { await loadDiff() }
                )
            }
        }
        .background(.regularMaterial)
        .task(id: reference) { await loadDiff() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(nsImage: reference.fileURL.fileIcon)
                .resizable()
                .frame(width: 16, height: 16)
            Text(reference.repositoryRelativePath)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)

            GitStatusBadge(kind: reference.kind, staged: reference.stage == .staged)

            Spacer()

            Button { panel.openFile(reference.fileURL) } label: {
                Image(systemName: "doc.text")
            }
            .buttonStyle(.borderless)
            .help("Open File")

            Button { panel.close() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Close")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func loadDiff() async {
        isLoading = true
        do {
            presentation = try await GitRepository.shared.diffFilePresentation(for: reference)
        } catch {
            presentation = DiffFilePresentation(message: "Failed to load diff: \(error.localizedDescription)")
        }
        isLoading = false
    }
}

// MARK: - Hunk List

struct DiffHunkListView: View {
    let hunks: [DiffHunk]
    let reference: GitDiffReference
    let fileExtension: String
    let onReload: () async -> Void

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(hunks) { hunk in
                    DiffHunkView(
                        hunk: hunk,
                        reference: reference,
                        fileExtension: fileExtension,
                        onReload: onReload
                    )
                }
            }
        }
    }
}

// MARK: - Single Hunk

struct DiffHunkView: View {
    let hunk: DiffHunk
    let reference: GitDiffReference
    let fileExtension: String
    let onReload: () async -> Void

    var body: some View {
        VStack(spacing: 0) {
            hunkHeader
            HunkTextView(hunk: hunk, fileExtension: fileExtension)
                .frame(height: CGFloat(hunk.lines.count) * HunkTextViewConstants.lineHeight)
        }
    }

    private var hunkHeader: some View {
        HStack(spacing: 8) {
            Text(hunk.header)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            if reference.stage == .unstaged {
                Button("Discard", role: .destructive) {
                    Task { await applyHunk(reverse: true, cached: false) }
                }
                .controlSize(.small)

                Button("Stage") {
                    Task { await applyHunk(reverse: false, cached: true) }
                }
                .controlSize(.small)
            } else {
                Button("Unstage") {
                    Task { await applyHunk(reverse: true, cached: true) }
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.background.tertiary)
    }

    private func applyHunk(reverse: Bool, cached: Bool) async {
        do {
            try await GitRepository.shared.applyPatch(
                hunk.patchText,
                reverse: reverse,
                cached: cached,
                at: reference.repositoryRootURL
            )
            await onReload()
        } catch {
            print("Failed to apply hunk: \(error)")
        }
    }
}

// MARK: - AppKit NSTextView per hunk

enum HunkTextViewConstants {
    static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    static let lineHeight: CGFloat = 17
    static let gutterWidth: CGFloat = 72
    static let lineNumFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
}

struct HunkTextView: NSViewRepresentable {
    let hunk: DiffHunk
    let fileExtension: String

    func makeNSView(context: Context) -> HunkNSTextView {
        let textView = HunkNSTextView()
        textView.configure(hunk: hunk, fileExtension: fileExtension)
        return textView
    }

    func updateNSView(_ textView: HunkNSTextView, context: Context) {
        // When the view scrolls into a lazy container, ensure appearance + redraw
        textView.appearance = textView.effectiveAppearance
        textView.needsDisplay = true
    }
}

/// NSTextView that draws line backgrounds and a line number gutter for a single hunk.
final class HunkNSTextView: NSTextView {
    private var lineData: [(kind: GitDiffLineKind?, oldNum: Int?, newNum: Int?)] = []

    func configure(hunk: DiffHunk, fileExtension: String) {
        let constants = HunkTextViewConstants.self

        // Set appearance before resolving any dynamic colors
        appearance = NSApp.effectiveAppearance

        isEditable = false
        isSelectable = true
        isRichText = false
        font = constants.font
        backgroundColor = .windowBackgroundColor
        drawsBackground = true
        textColor = .labelColor
        textContainerInset = NSSize(width: constants.gutterWidth, height: 0)
        isVerticallyResizable = false
        isHorizontallyResizable = false
        textContainer?.widthTracksTextView = true
        autoresizingMask = [.width]

        // Store line metadata
        lineData = hunk.lines.map { (kind: $0.kind, oldNum: $0.oldLineNumber, newNum: $0.newLineNumber) }

        // Build content string
        let source = hunk.lines.map(\.content).joined(separator: "\n")

        // Syntax highlight only — diff indication is handled by line backgrounds
        let attributed = NSMutableAttributedString(
            attributedString: SyntaxHighlighter.highlight(source, fileExtension: fileExtension)
        )

        textStorage?.setAttributedString(attributed)
        let text = source as NSString

        // Force layout so glyphs are generated before first draw
        layoutManager?.ensureLayout(forCharacterRange: NSRange(location: 0, length: text.length))
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Re-resolve appearance when added to a window
        if let window {
            appearance = window.effectiveAppearance
            needsDisplay = true
        }
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)

        guard let layoutManager = self.layoutManager,
              let textContainer = self.textContainer
        else { return }

        let constants = HunkTextViewConstants.self
        let text = self.string as NSString
        let containerOrigin = self.textContainerOrigin
        let gutterWidth = constants.gutterWidth

        // Draw gutter background
        let gutterRect = NSRect(x: 0, y: rect.minY, width: gutterWidth, height: rect.height)
        NSColor.controlBackgroundColor.withAlphaComponent(0.3).setFill()
        gutterRect.fill()

        // Draw gutter separator
        NSColor.separatorColor.withAlphaComponent(0.15).setStroke()
        NSBezierPath.strokeLine(
            from: NSPoint(x: gutterWidth - 0.5, y: rect.minY),
            to: NSPoint(x: gutterWidth - 0.5, y: rect.maxY)
        )

        guard text.length > 0 else { return }

        let fullRange = layoutManager.glyphRange(forBoundingRect: rect, in: textContainer)
        let charRange = layoutManager.characterRange(forGlyphRange: fullRange, actualGlyphRange: nil)

        let lineNumAttrs: [NSAttributedString.Key: Any] = [
            .font: constants.lineNumFont,
            .foregroundColor: NSColor.secondaryLabelColor,
        ]

        let colWidth: CGFloat = (gutterWidth - 8) / 2

        text.enumerateSubstrings(in: charRange, options: [.byLines, .substringNotRequired]) { _, substringRange, enclosingRange, _ in
            let lineIdx = self.lineIndex(forCharacterIndex: substringRange.location)
            guard lineIdx < self.lineData.count else { return }

            let glyphRange = layoutManager.glyphRange(forCharacterRange: enclosingRange, actualCharacterRange: nil)
            var lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            lineRect.origin.y += containerOrigin.y

            // Draw line background
            if let kind = self.lineData[lineIdx].kind {
                let bgColor: NSColor = kind == .added
                    ? .systemGreen.withAlphaComponent(0.12)
                    : .systemRed.withAlphaComponent(0.12)
                var fullLineRect = lineRect
                fullLineRect.origin.x = gutterWidth
                fullLineRect.size.width = self.bounds.width - gutterWidth
                bgColor.setFill()
                fullLineRect.fill()
            }

            let y = lineRect.minY
            let data = self.lineData[lineIdx]

            // Old line number
            if let old = data.oldNum {
                let str = "\(old)" as NSString
                let size = str.size(withAttributes: lineNumAttrs)
                str.draw(at: NSPoint(x: colWidth - size.width + 2, y: y), withAttributes: lineNumAttrs)
            }

            // New line number
            if let new = data.newNum {
                let str = "\(new)" as NSString
                let size = str.size(withAttributes: lineNumAttrs)
                str.draw(at: NSPoint(x: colWidth + 4 + (colWidth - size.width), y: y), withAttributes: lineNumAttrs)
            }
        }
    }

    private func lineIndex(forCharacterIndex index: Int) -> Int {
        let text = self.string as NSString
        var lineIdx = 0
        var i = 0
        while i < index && i < text.length {
            if text.character(at: i) == 0x0A { lineIdx += 1 }
            i += 1
        }
        return lineIdx
    }
}
