import SwiftUI

struct WorkspaceInfoView: View {
    let workspace: Workspace

    var body: some View {
        Form {
            Section("Workspace") {
                LabeledContent("Name", value: workspace.name)
                LabeledContent("Tabs", value: "\(workspace.tabs.count)")
            }

            if let tab = workspace.selectedTab {
                Section("Current Tab") {
                    LabeledContent("Title", value: tab.title)
                    LabeledContent("Directory", value: tab.displayDirectory.isEmpty ? "—" : tab.displayDirectory)
                    LabeledContent("Process Running", value: tab.hasChildProcess ? "Yes" : "No")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 320, height: 220)
    }
}
