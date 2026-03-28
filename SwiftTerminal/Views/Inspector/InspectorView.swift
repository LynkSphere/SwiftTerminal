import SwiftUI

struct InspectorView: View {
    let directoryURL: URL
    @Environment(AppState.self) private var appState

    private var spacerWidth: CGFloat {
        max(appState.inspectorWidth - 40, 0)
    }

    var body: some View {
        NavigationStack {
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { width in
                    appState.inspectorWidth = width
                }
                .toolbar {
                    //                if appState.showingInspector {
                    //                    ToolbarItem(placement: .primaryAction) {
                    //                        Picker("Inspector", selection: Bindable(appState).selectedInspectorTab) {
                    //                            ForEach(InspectorTab.allCases) { tab in
                    //                                Image(systemName: tab.icon)
                    //                                    .help(tab.label)
                    //                                    .tag(tab)
                    //                            }
                    //                        }
                    //                        .pickerStyle(.segmented)
                    //                    }
                    //                }
                    
//                    if appState.showingInspector {
//                        ToolbarItem(placement: .destructiveAction) {
//                            Button {
//                                changeWorkspaceDirectory()
//                            } label: {
//                                Image(systemName: "folder.badge.plus")
//                            }
//                            .help("Change Workspace Directory")
//                        }
//                    }
                    
                    ToolbarItem(placement: .automatic) {
                        Color.clear
                            .frame(width: spacerWidth, height: 0)
                    }
                    .sharedBackgroundVisibility(.hidden)

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
        case .extensions:
            ContentUnavailableView("Extensions", systemImage: "puzzlepiece.extension", description: Text("No extensions installed."))
        }
    }

    private func changeWorkspaceDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a new workspace directory"
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            appState.selectedWorkspace?.directory = url.path
            appState.selectedWorkspace?.name = url.lastPathComponent
        }
    }
}
