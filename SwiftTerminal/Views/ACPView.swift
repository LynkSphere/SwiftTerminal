import SwiftUI

struct ACPView: View {
    let chat: Chat

    @State private var isPreparingInitialScroll = true

    private var session: ACPSession { chat.session }
    private var messages: [Message] { chat.messages }

    private var permissionModeBinding: Binding<PermissionMode> {
        Binding(
            get: { chat.permissionMode },
            set: { newMode in
                chat.permissionMode = newMode
                session.applyPermissionMode(newMode)
            }
        )
    }

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

                ToolbarItem(placement: .automatic) {
                    Picker(selection: permissionModeBinding) {
                        ForEach(PermissionMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    } label: {
                        Label(chat.permissionMode.label, systemImage: "lock.shield")
                    }
                    .pickerStyle(.menu)
                    .help(chat.permissionMode.description)
                }
            }
            .overlay {
                if isPreparingInitialScroll {
                    ZStack {
                        Rectangle()
                            .fill(.background)
                        ProgressView()
                            .controlSize(.large)
                    }
                }
            }
            .safeAreaBar(edge: .bottom) {
                ACPInputArea(chat: chat)
            }
            .imageDropHandler(chat: chat)
            .onChange(of: messages.count) {
                guard !isPreparingInitialScroll else { return }
                withAnimation {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .task(id: chat.id) {
                isPreparingInitialScroll = true
                try? await Task.sleep(for: .milliseconds(50))
                proxy.scrollTo("bottom", anchor: .bottom)
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                isPreparingInitialScroll = false
            }
        }
    }
}
