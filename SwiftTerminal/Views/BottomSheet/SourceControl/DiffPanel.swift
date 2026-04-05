import SwiftUI

struct DiffPanel: View {
    let reference: GitDiffReference
    @State private var presentation: GitDiffPresentation?
    @State private var filePresentation: DiffFilePresentation?
    @State private var isLoading = true

    @Environment(EditorPanel.self) private var panel

    var body: some View {
        PanelLayout {
            Image(nsImage: reference.fileURL.fileIcon)
                .resizable()
                .frame(width: 16, height: 16)
            Text(reference.repositoryRelativePath)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
            GitStatusBadge(kind: reference.kind, staged: reference.stage != .unstaged)
            if let presentation, !presentation.lineKinds.isEmpty {
                diffStats(presentation.lineKinds)
            }
        } actions: {
            Button { panel.openFile(reference.fileURL) } label: {
                Image(systemName: "doc.text")
            }
            .buttonStyle(.borderless)
            .help("Open File")
        } content: {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = presentation?.string, presentation?.lineKinds.isEmpty == true, !message.isEmpty {
                ContentUnavailableView {
                    Text(message)
                        .foregroundStyle(.secondary)
                }
            } else if let presentation, !presentation.string.isEmpty {
                DiffTextEditor(
                    presentation: presentation,
                    fileExtension: reference.fileURL.pathExtension.lowercased(),
                    hunks: filePresentation?.hunks ?? [],
                    reference: reference,
                    onReload: { await loadDiff() }
                )
            } else {
                ContentUnavailableView {
                    Text("No diff available.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task(id: reference) { await loadDiff() }
    }

    @ViewBuilder
    private func diffStats(_ lineKinds: [Int: GitDiffLineKind]) -> some View {
        let added = lineKinds.values.filter { $0 == .added }.count
        let removed = lineKinds.values.filter { $0 == .removed }.count
        HStack(spacing: 4) {
            if added > 0 {
                Text("+\(added)")
                    .foregroundStyle(.green)
            }
            if removed > 0 {
                Text("-\(removed)")
                    .foregroundStyle(.red)
            }
        }
        .font(.caption.monospacedDigit())
    }

    private func loadDiff() async {
        isLoading = true
        do {
            async let fullContext = GitRepository.shared.fullContextDiffPresentation(for: reference)
            async let hunkBased = GitRepository.shared.diffFilePresentation(for: reference)
            let (full, hunks) = try await (fullContext, hunkBased)
            presentation = full
            filePresentation = hunks
        } catch {
            presentation = GitDiffPresentation(message: "Failed to load diff: \(error.localizedDescription)")
            filePresentation = nil
        }
        isLoading = false
    }
}
