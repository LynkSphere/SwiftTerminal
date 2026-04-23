import SwiftUI

struct ACPView: View {
    let chat: Chat

    private var session: ACPSession { chat.session }
    private var messages: [Message] { chat.messages }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(messages) { message in
                    MessageRow(message: message)
                        .listRowSeparator(.hidden)
                }

                if let error = session.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .listRowSeparator(.hidden)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.red)
                        .padding(.vertical)
                }

                Color.clear
                    .frame(height: 1)
                    .id("bottom")
                    .listRowSeparator(.hidden)
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        if session.isConnected {
                            session.disconnect()
                        }
                    } label: {
                        if !session.isConnected && !session.isConnecting {
                            Label("Disconnected", systemImage: "bolt.slash")
                        } else if session.isConnecting {
                            ProgressView()
                            .controlSize(.small)
                        } else if session.isConnected {
                            Label("Connected", systemImage: "bolt.fill")
                        }
                    }
                }
            }
            .safeAreaBar(edge: .bottom) {
                ACPInputArea(chat: chat)
            }
            .onChange(of: messages.count) {
                withAnimation {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }
}
