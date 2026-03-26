import SwiftUI

struct EditorPanelView: View {
    let directoryURL: URL
    @Environment(EditorPanel.self) private var panel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Button { panel.goBack() } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .disabled(!panel.canGoBack)
            .help("Back")

            Button { panel.goForward() } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .disabled(!panel.canGoForward)
            .help("Forward")

            Divider()
                .frame(height: 15)
                .padding(.horizontal, 3)
//                .padding(.leading, 1)

            contentTitle

            Spacer()

            contentActions

            Button { panel.toggle() } label: {
                Image(systemName: "inset.filled.bottomthird.square")
                    .foregroundStyle(.accent)
            }
            .buttonStyle(.borderless)
            .help("Toggle Panel")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThickMaterial)
    }

    @ViewBuilder
    private var contentTitle: some View {
        switch panel.content {
        case .file(let url):
            Image(nsImage: url.fileIcon)
                .resizable()
                .frame(width: 16, height: 16)
            Text(url.relativePath(from: directoryURL))
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
            if panel.isDirty {
                Circle()
                    .fill(.secondary)
                    .frame(width: 6, height: 6)
                    .help("Unsaved changes")
            }
        case .diff(let ref):
            Image(nsImage: ref.fileURL.fileIcon)
                .resizable()
                .frame(width: 16, height: 16)
            Text(ref.repositoryRelativePath)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
            GitStatusBadge(kind: ref.kind, staged: ref.stage == .staged)
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private var contentActions: some View {
        switch panel.content {
        case .file:
            Button { panel.saveRequested = true } label: {
                Image(systemName: "opticaldiscdrive")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!panel.isDirty)
            .help("Save")
        case .diff(let ref):
            Button { panel.openFile(ref.fileURL) } label: {
                Image(systemName: "doc.text")
            }
            .buttonStyle(.borderless)
            .help("Open File")
        case .none:
            EmptyView()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch panel.content {
        case .file(let url):
            FileEditorPanel(fileURL: url, directoryURL: directoryURL)
        case .diff(let ref):
            DiffPanel(reference: ref)
        case .none:
            EmptyView()
        }
    }
}
