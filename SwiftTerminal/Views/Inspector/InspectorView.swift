import SwiftUI

struct InspectorView: View {
    let directoryURL: URL
    @Environment(AppState.self) private var appState

    private var spacerWidth: CGFloat {
        max(appState.inspectorWidth - 50, 0)
    }

    var body: some View {
        tabContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                appState.inspectorWidth = width
            }
            .toolbar {
                if appState.showingInspector {
                    ToolbarItem(placement: .automatic) {
                        Color.clear
                            .frame(width: spacerWidth, height: 0)
                    }
                    .sharedBackgroundVisibility(.hidden)
                }

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
        case .terminal:
            TerminalInspectorView()
        }
    }

}
