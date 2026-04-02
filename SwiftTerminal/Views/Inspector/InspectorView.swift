import SwiftUI

struct InspectorView: View {
    let workspace: Workspace
    @Environment(AppState.self) private var appState

    private var state: InspectorViewState { workspace.inspectorState }

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
                Picker("Inspector", selection: Bindable(state).selectedTab) {
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
        switch state.selectedTab {
        case .files:
            FileTreeView(directoryURL: workspace.url, state: state.fileTree)
        case .search:
            SearchInspectorView(directoryURL: workspace.url, state: state.search)
        case .git:
            GitInspectorView(directoryURL: workspace.url, state: state.git)
        case .commands:
            CommandsInspectorView(workspace: workspace, state: state.commands)
        }
    }

}
