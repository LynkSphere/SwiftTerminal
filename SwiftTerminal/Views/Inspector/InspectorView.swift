import SwiftUI

struct InspectorView: View {
    let directoryURL: URL
    @Environment(AppState.self) private var appState
    @Environment(EditorPanel.self) private var editorPanel
    
    var body: some View {
        tabContent
            .toolbar {
                ToolbarSpacer(.flexible)

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        appState.showingInspector.toggle()
                    } label: {
                        Image(systemName: "sidebar.trailing")
                    }
                }
            }
            .safeAreaBar(edge: .top) {
                Picker("Inspector", selection: Bindable(appState).selectedInspectorTab) {
                    ForEach(InspectorTab.allCases) { tab in
                        Image(systemName: tab.icon)
                            .help(tab.label)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.large)
                .buttonSizing(.flexible)
                .labelsHidden()
                .padding(.horizontal, 10)
            }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch appState.selectedInspectorTab {
        case .files:
            FileTreeView(directoryURL: directoryURL)
        case .search:
            SearchInspectorView(directoryURL: directoryURL)
        case .git:
            GitInspectorView(directoryURL: directoryURL)
        }
    }

}
