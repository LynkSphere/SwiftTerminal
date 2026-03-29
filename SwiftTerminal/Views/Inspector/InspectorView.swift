import SwiftUI

struct InspectorView: View {
    let directoryURL: URL
    @Environment(AppState.self) private var appState
    @State private var inspectorWidth: CGFloat = 0
    
    var body: some View {
        tabContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                inspectorWidth = width
            }
            .toolbar {
                if appState.showingInspector {
                    ToolbarItem(placement: .automatic) {
                        Button {
                            appState.panelToggleToken = UUID()
                        } label: {
                            Image(systemName: "inset.filled.bottomthird.square")
                        }
                    }

                    ToolbarItem(placement: .automatic) {
                        Color.clear
                            .frame(width: max(inspectorWidth - 110, 0), height: 0)
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
