import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct WorkspaceRow: View {
    @Environment(AppState.self) private var appState
    @Environment(WorkspaceStore.self) private var store

    let workspace: Workspace

    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var customIconImage: NSImage?
    @State private var loadedIconFilename: String?

    private var busyCount: Int {
        workspace.terminals.filter(\.hasChildProcess).count
    }

    private var hasBell: Bool {
        workspace.terminals.contains(where: \.hasBellNotification)
    }

    private var hasRunningCommand: Bool {
        workspace.commands.contains(where: \.hasChildProcess)
    }

    private func reloadCustomIconIfNeeded() {
        let filename = workspace.customIconFilename
        guard filename != loadedIconFilename else { return }
        loadedIconFilename = filename
        if let url = workspace.customIconURL {
            customIconImage = NSImage(contentsOf: url)
        } else {
            customIconImage = nil
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Label {
                Text(workspace.name)
                    .lineLimit(1)
            } icon: {
                if let nsImage = customIconImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                        .clipShape(.rect(cornerRadius: 6))
                } else if workspace.projectType != .unknown {
                    Image(workspace.projectType.iconName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: "folder")
                }
            }

            Spacer(minLength: 4)

            if !workspace.scratchPad.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    appState.scratchPadRequest = workspace
                    appState.selectedWorkspace = workspace
                } label: {
                    Image(systemName: "note.text")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open Scratch Pad")
            }

            if hasRunningCommand {
                Button {
                    appState.selectedWorkspace = workspace
                    workspace.inspectorState.selectedTab = .commands
                } label: {
                    Image(systemName: "terminal.fill")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("A command is running")
            }
        }
        .badge(hasBell ? Text("") : (busyCount > 0 ? Text("\(busyCount)") : nil))
        .badgeProminence(hasBell ? .increased : .standard)
        .alert("Rename Workspace", isPresented: $isRenaming) {
            TextField("Workspace Name", text: $renameText)
            Button("Cancel", role: .cancel) { }
            Button("Rename") {
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    workspace.name = trimmed
                }
            }
        }
        .contextMenu {
            RenameButton()

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([workspace.url])
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }

            Divider()

            Menu {
                Picker("Project Type", selection: Bindable(workspace).projectType) {
                    ForEach(ProjectType.allCases, id: \.self) { type in
                        Label {
                            Text(type.displayName)
                        } icon: {
                            if !type.iconName.isEmpty {
                                Image(type.iconName)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 18, height: 18)
                            }
                        }
                        .tag(type)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()

                Divider()

                Button("Auto-Detect") {
                    workspace.detectProjectType()
                }
            } label: {
                Label("Project Type", systemImage: "shippingbox")
            }

            Button {
                chooseCustomIcon()
            } label: {
                Label("Choose Icon…", systemImage: "photo")
            }

            if workspace.customIconFilename != nil {
                Button {
                    workspace.clearCustomIcon()
                } label: {
                    Label("Reset Icon", systemImage: "arrow.uturn.backward")
                }
            }

            Divider()

            Button {
                workspace.killAllRunningTerminals()
            } label: {
                Label("Kill All Terminals", systemImage: "xmark.octagon")
            }
            .disabled(!workspace.hasRunningTerminals)

            Divider()

            Button {
                toggleArchive()
            } label: {
                Label(
                    workspace.isArchived ? "Unarchive" : "Archive",
                    systemImage: workspace.isArchived ? "tray.and.arrow.up" : "archivebox"
                )
            }

            Button(role: .destructive) {
                if appState.selectedWorkspace === workspace {
                    appState.selectedWorkspace = nil
                    appState.selectedTerminal = nil
                }
                store.deleteWorkspace(workspace)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .renameAction {
            renameText = workspace.name
            isRenaming = true
        }
        .task(id: workspace.customIconFilename) {
            reloadCustomIconIfNeeded()
        }
    }

    private func chooseCustomIcon() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.icns, .png, .jpeg]
        panel.message = "Choose an icon image"
        panel.prompt = "Set Icon"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try workspace.setCustomIcon(from: url)
        } catch {
            print("WorkspaceRow: failed to set custom icon: \(error)")
        }
    }

    private func toggleArchive() {
        if !workspace.isArchived {
            if appState.selectedWorkspace === workspace {
                appState.selectedWorkspace = nil
                appState.selectedTerminal = nil
            }
            workspace.killAllRunningTerminals()
        }
        workspace.isArchived.toggle()
    }
}
