import SwiftUI

struct InspectorView: View {
    let directoryURL: URL
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    
                    ToolbarSpacer()
                    
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            appState.showingInspector.toggle()
                        } label: {
                            Image(systemName: "sidebar.trailing")
                        }
                    }
                }
                .safeAreaBar(edge: .top) {
                    InspectorTabBar(
                        tabs: InspectorTab.allCases,
                        selection: Bindable(appState).selectedInspectorTab
                    )
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
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

private struct InspectorTabBar: NSViewRepresentable {
    let tabs: [InspectorTab]
    @Binding var selection: InspectorTab

    func makeNSView(context: Context) -> NSView {
        let container = NSView()

        let control = NSSegmentedControl()
        control.controlSize = .large
        control.segmentCount = tabs.count
        control.target = context.coordinator
        control.action = #selector(Coordinator.segmentChanged(_:))

        for (index, tab) in tabs.enumerated() {
            control.setImage(
                NSImage(systemSymbolName: tab.icon, accessibilityDescription: tab.label),
                forSegment: index
            )
            control.setToolTip(tab.label, forSegment: index)
        }

        control.selectedSegment = selection.rawValue

        control.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(control)
        NSLayoutConstraint.activate([
            control.topAnchor.constraint(equalTo: container.topAnchor),
            control.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            control.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            control.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        context.coordinator.control = control
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        context.coordinator.control?.selectedSegment = selection.rawValue
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    final class Coordinator: NSObject {
        @Binding var selection: InspectorTab
        weak var control: NSSegmentedControl?

        init(selection: Binding<InspectorTab>) {
            _selection = selection
        }

        @objc func segmentChanged(_ sender: NSSegmentedControl) {
            if let tab = InspectorTab(rawValue: sender.selectedSegment) {
                selection = tab
            }
        }
    }
}
