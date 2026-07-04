import SwiftUI

struct AppCommands: Commands {
    @Bindable var appState: AppState
    let updater: UpdaterManager
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.editorPanel) private var editorPanel
    @FocusedValue(\.isMainWindow) private var isMainWindow
    @AppStorage("showHiddenFiles") var showHiddenFiles = false
    @AppStorage(EditorFontSize.key) private var editorFontSize: Double = EditorFontSize.default

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
            
            // Override the system's File > Close (Cmd+W) to close the active tab instead of the window
            CommandGroup(after: .newItem) {
                Button {
                    guard let workspace = appState.selectedWorkspace,
                          let terminal = appState.selectedTerminal else { return }
                    // In a split tab, Cmd+W closes the focused pane, not the tab.
                    if appState.isTabSplit(terminal) {
                        let pane = appState.resolvedFocusedPane(for: terminal)
                        if pane.hasChildProcess {
                            appState.panePendingClose = pane
                        } else {
                            appState.closePane(pane, in: terminal)
                        }
                        return
                    }
                    guard workspace.terminals.count > 1 else { return }
                    if terminal.hasChildProcess {
                        appState.terminalPendingClose = terminal
                    } else {
                        let next = workspace.terminalAfter(terminal) ?? workspace.terminalBefore(terminal)
                        workspace.closeTerminal(terminal)
                        appState.selectedTerminal = next
                    }
                } label: {
                    Label("Close Tab", systemImage: "xmark.square")
                }
                .keyboardShortcut("w", modifiers: .command)
            }

            CommandGroup(replacing: .toolbar) {
                Button {
                    appState.selectedTerminal?.increaseFontSize()
                    editorFontSize = min(editorFontSize + 0.5, EditorFontSize.max)
                } label: {
                    Label("Zoom In", systemImage: "plus.magnifyingglass")
                }
                .keyboardShortcut("+", modifiers: .command)

                Button {
                    appState.selectedTerminal?.decreaseFontSize()
                    editorFontSize = max(editorFontSize - 0.5, EditorFontSize.min)
                } label: {
                    Label("Zoom Out", systemImage: "minus.magnifyingglass")
                }
                .keyboardShortcut("-", modifiers: .command)

                Button {
                    appState.selectedTerminal?.resetFontSize()
                    editorFontSize = EditorFontSize.default
                } label: {
                    Label("Actual Size", systemImage: "1.magnifyingglass")
                }
                .keyboardShortcut("O", modifiers: .command)

                Divider()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        editorPanel?.toggle()
                    }
                } label: {
                    Label("Toggle Bottom Panel", systemImage: "rectangle.bottomhalf.inset.filled")
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

                Button {
                    appState.showArchivedWorkspaces.toggle()
                } label: {
                    Label(
                        appState.showArchivedWorkspaces ? "Hide Archived Workspaces" : "Show Archived Workspaces",
                        systemImage: appState.showArchivedWorkspaces ? "tray.and.arrow.up" : "archivebox"
                    )
                }
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
                    if command.hasChildProcess {
                        appState.pendingRunReplacement = command
                    } else {
                        workspace.runCommand(command)
                    }
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(appState.selectedWorkspace?.defaultCommand == nil)

                Button {
                    guard let workspace = appState.selectedWorkspace,
                          let command = workspace.defaultCommand else { return }
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

            CommandMenu("Terminal") {
                Button {
                    guard let workspace = appState.selectedWorkspace else { return }
                    let terminal = workspace.addTerminal(
                        currentDirectory: appState.selectedTerminal?.currentDirectory,
                        after: appState.selectedTerminal
                    )
                    appState.selectedTerminal = terminal
                } label: {
                    Label("New Tab", systemImage: "plus.square")
                }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(appState.selectedWorkspace == nil)

                Button {
                    guard let workspace = appState.selectedWorkspace else { return }
                    let terminal = workspace.addTerminal(
                        currentDirectory: workspace.directory,
                        after: appState.selectedTerminal
                    )
                    appState.selectedTerminal = terminal
                } label: {
                    Label("New Tab in Workspace", systemImage: "plus.square.on.square")
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(appState.selectedWorkspace == nil)

                Divider()

                Button {
                    guard let workspace = appState.selectedWorkspace,
                          let current = appState.selectedTerminal,
                          let prev = workspace.terminalBefore(current) else { return }
                    appState.selectedTerminal = prev
                } label: {
                    Label("Select Previous Tab", systemImage: "chevron.left.square")
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled((appState.selectedWorkspace?.terminals.count ?? 0) < 2)

                Button {
                    guard let workspace = appState.selectedWorkspace,
                          let current = appState.selectedTerminal,
                          let next = workspace.terminalAfter(current) else { return }
                    appState.selectedTerminal = next
                } label: {
                    Label("Select Next Tab", systemImage: "chevron.right.square")
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled((appState.selectedWorkspace?.terminals.count ?? 0) < 2)

                Divider()

                Button {
                    appState.actionTargetPane?.clearTerminal()
                } label: {
                    Label("Clear Terminal", systemImage: "clear")
                }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(appState.actionTargetPane?.localProcessTerminalView == nil)

                Divider()

                Button {
                    appState.splitActivePane(.horizontal)
                } label: {
                    Label("Split Right", systemImage: "rectangle.split.2x1")
                }
                .keyboardShortcut("\\", modifiers: .command)
                .disabled(appState.selectedTerminal == nil)

                Button {
                    appState.splitActivePane(.vertical)
                } label: {
                    Label("Split Down", systemImage: "rectangle.split.1x2")
                }
                .keyboardShortcut("\\", modifiers: [.command, .shift])
                .disabled(appState.selectedTerminal == nil)

                Divider()

                Button {
                    appState.movePaneFocus(.left)
                } label: {
                    Label("Focus Pane Left", systemImage: "arrow.left")
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(appState.selectedTerminal.map { !appState.isTabSplit($0) } ?? true)

                Button {
                    appState.movePaneFocus(.right)
                } label: {
                    Label("Focus Pane Right", systemImage: "arrow.right")
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(appState.selectedTerminal.map { !appState.isTabSplit($0) } ?? true)

                Button {
                    appState.movePaneFocus(.up)
                } label: {
                    Label("Focus Pane Up", systemImage: "arrow.up")
                }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(appState.selectedTerminal.map { !appState.isTabSplit($0) } ?? true)

                Button {
                    appState.movePaneFocus(.down)
                } label: {
                    Label("Focus Pane Down", systemImage: "arrow.down")
                }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(appState.selectedTerminal.map { !appState.isTabSplit($0) } ?? true)
            }
        }
    }
}
