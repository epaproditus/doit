import PhotosUI
import SwiftUI

struct ChatDetailView: View {
    let conversationID: UUID

    @Environment(ConversationStore.self) private var conversationStore

    @State private var messageText = ""
    @State private var isLoading = false
    @State private var isSending = false
    @State private var photoSelections: [PhotosPickerItem] = []

    var body: some View {
        VStack(spacing: 0) {
            messageList

            Divider()

            composer
        }
        .background(AppSemanticColors.screenBackground)
        .navigationTitle(conversationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        Task { await conversationStore.deleteConversation(id: conversationID) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task {
            await conversationStore.loadMessages(conversationID: conversationID)
        }
        .task(id: conversationID) {
            TodoRealtimeHub.beginConversationWatch(
                conversationID: conversationID,
                handlers: .init(
                    onMessages: { [weak conversationStore] in
                        await conversationStore?.reloadMessages(conversationID: conversationID)
                    }
                )
            )
        }
        .onDisappear {
            TodoRealtimeHub.endConversationWatch()
        }
    }

    private var conversationTitle: String {
        conversationStore.conversations.first(where: { $0.id == conversationID })?.title ?? "Chat"
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    let messages = conversationStore.messagesByConversationID[conversationID] ?? []
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }

                    if isSending {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Thinking…")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    }
                }
                .padding()
            }
            .onChange(of: conversationStore.messagesByConversationID[conversationID]?.count ?? 0) { _, _ in
                if let last = conversationStore.messagesByConversationID[conversationID]?.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            PhotosPicker(
                selection: $photoSelections,
                maxSelectionCount: 5,
                matching: .images
            ) {
                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .foregroundColor(AppSemanticColors.accentColor)
            }

            TextField("Message…", text: $messageText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...6)

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(
                        messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? .secondary.opacity(0.3)
                            : AppSemanticColors.accentColor
                    )
            }
            .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)

            Button(action: {}) {
                Image(systemName: "mic")
                    .font(.system(size: 20))
                    .foregroundColor(AppSemanticColors.accentColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messageText = ""
        isSending = true
        Task {
            _ = await conversationStore.sendMessage(
                conversationID: conversationID,
                body: text
            )
            isSending = false
        }
    }
}

private struct MessageBubble: View {
    let message: ConversationMessage

    var body: some View {
        HStack {
            if message.role == "user" {
                Spacer(minLength: 60)
            }

            Text(message.body)
                .font(.body)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(background)
                .foregroundColor(foreground)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            if message.role == "assistant" {
                Spacer(minLength: 60)
            }
        }
    }

    private var background: Color {
        message.role == "user"
            ? AppSemanticColors.accentColor
            : AppSemanticColors.cardBackground
    }

    private var foreground: Color {
        message.role == "user"
            ? .white
            : AppSemanticColors.primary
    }
}
