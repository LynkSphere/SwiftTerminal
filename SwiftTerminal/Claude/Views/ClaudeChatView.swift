import SwiftUI

extension String {
    nonisolated static let bottomID = "bottomID"
}

struct ClaudeChatView: View {
    let service: ClaudeService

    var body: some View {
        ScrollViewReader { proxy in
            List {
                MessageListView(service: service)

                ErrorBarView(service: service)
                    .listRowSeparator(.hidden)

                Color.clear
                    .frame(height: 1)
                    .listRowSeparator(.hidden)
                    .id(String.bottomID)
            }
            .task {
                service.scrollProxy = proxy
                // Scroll to bottom once messages are rendered
                service.scrollToBottom(delay: 0.25)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSScrollView.willStartLiveScrollNotification)) { _ in
                if service.isStreaming {
                    service.userDidScroll = true
                }
            }
        }
        .overlay {
            if service.messages.isEmpty {
                ContentUnavailableView {
                    Label("Claude Code", image: "claude.symbols")
                } description: {
                    Text("Do anything about this workspace")
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: service.pendingApproval != nil)
        .animation(.easeInOut(duration: 0.2), value: service.pendingQuestion != nil)
        .toolbar {
            ToolbarContentView(service: service)
        }
        .safeAreaBar(edge: .bottom) {
            VStack(spacing: 0) {
                if let approval = service.pendingApproval {
                    ApprovalPanelView(service: service, approval: approval)
                }
                if let question = service.pendingQuestion {
                    QuestionPanelView(service: service, question: question)
                }
                InputBarView(service: service)
            }
        }
    }
}
