import SwiftUI
import UniformTypeIdentifiers

extension String {
    nonisolated static let bottomID = "bottomID"
}

struct ClaudeChatView: View {
    let service: ClaudeService

    private func handleImageDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasRepresentationConforming(toTypeIdentifier: UTType.image.identifier) {
                handled = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    let attachment = ImageAttachment(data: data, mediaType: "image/png")
                    Task { @MainActor in
                        service.imageAttachments.append(attachment)
                    }
                }
            }
        }
        return handled
    }

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
                service.scrollToBottom(delay: 0.5)
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
        .imagePasteHandler(service: service)
        .onDrop(of: [.image], isTargeted: nil) { providers in
            handleImageDrop(providers)
        }
        .animation(.easeInOut(duration: 0.2), value: service.pendingApproval != nil)
        .animation(.easeInOut(duration: 0.2), value: service.pendingQuestion != nil)
        .animation(.easeInOut(duration: 0.2), value: service.pendingPlanReview != nil)
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
                if service.pendingPlanReview != nil {
                    PlanReviewPanelView(service: service)
                }
                InputBarView(service: service)
            }
        }
    }
}
