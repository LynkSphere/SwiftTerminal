import SwiftUI

struct FileEditorPanel: View {
    let fileURL: URL
    @Environment(EditorPanel.self) private var panel
    @State private var content: String = ""
    @State private var savedContent: String = ""
    @State private var isLoaded = false
    @State private var isSaving = false
    @State private var errorMessage: String?

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
                    fileExtension: fileURL.pathExtension.lowercased()
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
            Text(fileURL.lastPathComponent)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)

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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveFile() {
        isSaving = true
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            savedContent = content
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}

// MARK: - NSTextView wrapper with syntax highlighting

struct HighlightedTextEditor: NSViewRepresentable {
    @Binding var text: String
    let fileExtension: String

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

        // Initial content
        let highlighted = SyntaxHighlighter.highlight(text, fileExtension: fileExtension)
        textView.textStorage?.setAttributedString(highlighted)

        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Only update if the binding changed externally (not from editing)
        if !context.coordinator.isEditing, textView.string != text {
            let highlighted = SyntaxHighlighter.highlight(text, fileExtension: fileExtension)
            textView.textStorage?.setAttributedString(highlighted)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: HighlightedTextEditor
        weak var textView: NSTextView?
        var isEditing = false
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
