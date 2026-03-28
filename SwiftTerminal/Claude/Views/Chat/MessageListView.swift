import SwiftUI

struct MessageListView: View {
    let messages: [ChatMessage]
    let isStreaming: Bool
    var activeTasks: [String: TaskEvent] = [:]
    var onStopTask: ((String) -> Void)?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(messages) { message in
                        MessageView(
                            message: message,
                            isStreaming: isStreaming
                                && message.id == messages.last?.id
                                && message.role == .assistant
                        )
                        .id(message.id)
                    }

                    if !activeTasks.isEmpty {
                        TaskProgressView(tasks: activeTasks, onStopTask: onStopTask)
                            .id("active-tasks")
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) {
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: messages.last?.blocks.count) {
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: messages.last?.text) {
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: activeTasks.count) {
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if !activeTasks.isEmpty {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo("active-tasks", anchor: .bottom)
            }
        } else if let last = messages.last {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}
