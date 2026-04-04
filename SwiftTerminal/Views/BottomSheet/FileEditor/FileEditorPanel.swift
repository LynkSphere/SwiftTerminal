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
    @Environment(\.showInFileTree) private var showInFileTree

    private var hasUnsavedChanges: Bool {
        isLoaded && content != savedContent
    }

    var body: some View {
        PanelLayout {
            Image(nsImage: fileURL.fileIcon)
                .resizable()
                .frame(width: 16, height: 16)
            Text(fileURL.relativePath(from: directoryURL))
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
            if panel.isDirty {
                Circle()
                    .fill(.secondary)
                    .frame(width: 6, height: 6)
                    .help("Unsaved changes")
            }
        } actions: {
            Button { showInFileTree(fileURL) } label: {
                Image(systemName: "sidebar.trailing")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("j", modifiers: [.command, .shift])
            .help("Show in File Tree")

            Button { panel.saveRequested = true } label: {
                Image(systemName: "opticaldiscdrive")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!panel.isDirty)
            .help("Save")
        } content: {
            if isLoaded {
                HighlightedTextEditor(
                    text: $content,
                    fileExtension: fileURL.pathExtension.lowercased(),
                    gutterDiff: gutterDiff,
                    highlightRequest: panel.highlightRequest
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
        .onChange(of: panel.saveRequested) { _, requested in
            if requested {
                saveFile()
                panel.saveRequested = false
            }
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
