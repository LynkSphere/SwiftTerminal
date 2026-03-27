import SwiftUI

struct SearchInspectorView: View {
    let directoryURL: URL

    @Environment(AppState.self) private var appState
    @Environment(EditorPanel.self) private var editorPanel
    @State private var model = SearchInspectorModel()
    @State private var expandedIDs: Set<UUID> = []
    @State private var selectedID: UUID?
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        List(selection: $selectedID) {
            ForEach(model.results) { fileResult in
                DisclosureGroup(isExpanded: binding(for: fileResult.id)) {
                    ForEach(fileResult.matches) { match in
                        matchRow(match)
                            .tag(match.id)
                    }
                } label: {
                    FileLabel(name: fileResult.relativePath, icon: fileResult.fileURL.fileIcon)
                }
                .tag(fileResult.id)
            }
        }
        .scrollContentBackground(.hidden)
        .safeAreaBar(edge: .top) {
            SearchField(text: $model.query) {
                Task {
                    await model.search(in: directoryURL)
                    expandedIDs = Set(model.results.map(\.id))
                }
            }
            .focused($isSearchFocused)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .padding(.top, 6)
        }
        .onChange(of: selectedID) { _, newID in
            guard let id = newID else { return }

            // Check if a file result was selected
            if let fileResult = model.results.first(where: { $0.id == id }) {
                editorPanel.openFile(fileResult.fileURL)
                return
            }

            // Check if a match was selected
            for fileResult in model.results {
                if let match = fileResult.matches.first(where: { $0.id == id }) {
                    editorPanel.openFileAndHighlight(
                        match.fileURL,
                        lineNumber: match.lineNumber,
                        columnRange: match.columnRange
                    )
                    return
                }
            }
        }
        .task(id: appState.searchFocusToken) {
            guard appState.searchFocusToken != nil else { return }
            try? await Task.sleep(for: .milliseconds(50))
            isSearchFocused = true
            appState.searchFocusToken = nil
        }
    }
    private func matchRow(_ match: SearchMatch) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("\(match.lineNumber)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(minWidth: 28, alignment: .trailing)

            Text(match.highlightedContent)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func binding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedIDs.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    expandedIDs.insert(id)
                } else {
                    expandedIDs.remove(id)
                }
            }
        )
    }
}
