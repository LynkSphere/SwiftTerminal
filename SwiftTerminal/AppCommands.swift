import SwiftUI

struct AppCommands: Commands {
    @Bindable var appState: AppState
    let updater: UpdaterManager
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.editorPanel) private var editorPanel
    @FocusedValue(\.isMainWindow) private var isMainWindow
    @AppStorage("showHiddenFiles") var showHiddenFiles = false
    @AppStorage("defaultChatMode") private var defaultChatMode: AgentProvider = .claude
    @AppStorage("defaultPermissionMode") private var defaultPermissionMode: PermissionMode = .bypassPermissions

    /// Whether the focused window is the main SwiftTerminal window.
    private var mainWindowActive: Bool { isMainWindow == true }

    var body: some Commands {
        // Replace the default "About SwiftTerminal" item with one that opens our
        // custom About window scene.
        CommandGroup(replacing: .appInfo) {
            Button("About SwiftTerminal") {
                openWindow(id: "about")
            }
        }

        // Sparkle "Check for Updates…" — placed right after the standard About item in the
        // app menu. Lives outside the `mainWindowActive` gate so it stays available
        // regardless of which window is focused.
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                updater.checkForUpdates()
            }
            .disabled(!updater.canCheckForUpdates)
        }

        if mainWindowActive {
            SidebarCommands()
            
            InspectorCommands()
            
            CommandGroup(after: .newItem) {
                Menu {
                    ForEach(AgentProvider.allCases, id: \.self) { provider in
                        Button {
                            guard let workspace = appState.selectedWorkspace else { return }
                            let chat = workspace.addChat(provider: provider, permissionMode: defaultPermissionMode)
                            appState.expandedWorkspaceIDs.insert("w:\(workspace.id.uuidString)")
                            appState.selectedChat = chat
                        } label: {
                            Label(provider.rawValue, image: provider.imageName)
                        }
                    }
                } label: {
                    Label("New Chat", systemImage: "plus.bubble")
                } primaryAction: {
                    guard let workspace = appState.selectedWorkspace else { return }
                    let chat = workspace.addChat(provider: defaultChatMode, permissionMode: defaultPermissionMode)
                    appState.expandedWorkspaceIDs.insert("w:\(workspace.id.uuidString)")
                    appState.selectedChat = chat
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(appState.selectedWorkspace == nil)
            }

            CommandGroup(replacing: .toolbar) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        editorPanel?.toggle()
                    }
                } label: {
                    Label("Toggle Editor Panel", systemImage: "rectangle.bottomhalf.inset.filled")
                }
                .keyboardShortcut("j", modifiers: .command)

                Divider()

                Button {
                    showHiddenFiles.toggle()
                } label: {
                    Label(
                        showHiddenFiles ? "Hide Hidden Files" : "Show Hidden Files",
                        systemImage: showHiddenFiles ? "eye.slash" : "eye"
                    )
                }
                .keyboardShortcut(".", modifiers: [.command, .shift])
            }

            CommandMenu("Inspector") {
                Button {
                    appState.showingInspector = true
                    appState.selectedWorkspace?.inspectorState.selectedTab = .files
                } label: {
                    Label("Files Navigator", systemImage: "folder")
                }
                .keyboardShortcut("1", modifiers: .command)

                Button {
                    appState.showingInspector = true
                    appState.selectedWorkspace?.inspectorState.selectedTab = .git
                } label: {
                    Label("Git Navigator", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                }
                .keyboardShortcut("2", modifiers: .command)

                Button {
                    appState.showingInspector = true
                    appState.selectedWorkspace?.inspectorState.selectedTab = .search
                } label: {
                    Label("Search Navigator", systemImage: "magnifyingglass")
                }
                .keyboardShortcut("3", modifiers: .command)

                Button {
                    appState.showingInspector = true
                    appState.selectedWorkspace?.inspectorState.selectedTab = .commands
                } label: {
                    Label("Command Runner", systemImage: "apple.terminal")
                }
                .keyboardShortcut("4", modifiers: .command)

                Divider()

                Button {
                    guard let workspace = appState.selectedWorkspace,
                          let command = workspace.defaultCommand else { return }
                    appState.showingInspector = true
                    workspace.runCommand(command)
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(appState.selectedWorkspace?.defaultCommand == nil || appState.selectedWorkspace?.defaultCommand?.hasChildProcess == true)

                Button {
                    guard let command = appState.selectedWorkspace?.defaultCommand else { return }
                    command.interrupt()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(appState.selectedWorkspace?.defaultCommand?.hasChildProcess != true)

                Divider()

                Button {
                    appState.showingInspector = true
                    appState.selectedWorkspace?.inspectorState.selectedTab = .search
                    appState.selectedWorkspace?.inspectorState.search.searchFocusTrigger += 1
                } label: {
                    Label("Find in Files", systemImage: "doc.text.magnifyingglass")
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Button {
                    appState.showingInspector = true
                    appState.selectedWorkspace?.inspectorState.selectedTab = .files
                    appState.selectedWorkspace?.inspectorState.fileTree.searchFocusTrigger += 1
                } label: {
                    Label("Go to File", systemImage: "doc.text.magnifyingglass")
                }
                .keyboardShortcut("p", modifiers: .command)
            }

            CommandGroup(after: .textEditing) {
                Button("Find…") {
                    let item = NSMenuItem()
                    item.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
                    NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: item)
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Find and Replace…") {
                    let item = NSMenuItem()
                    item.tag = Int(NSFindPanelAction.setFindString.rawValue)
                    NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: item)
                }
                .keyboardShortcut("f", modifiers: [.command, .option])
            }
        }
    }
}
