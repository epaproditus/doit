import SwiftUI

struct ChatListView: View {
    let userID: UUID

    @Environment(ConversationStore.self) private var conversationStore
    @Environment(AuthModel.self) private var auth
    @Environment(TodoStore.self) private var todoStore

    @State private var navigationPath = NavigationPath()
    @State private var showNewChat = false
    @State private var isLoading = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                AppSemanticColors.screenBackground.ignoresSafeArea()

                if conversationStore.conversations.isEmpty && !conversationStore.isInitialLoading {
                    emptyState
                } else {
                    listContent
                }
            }
            .navigationTitle("Chat")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showNewChat = true }) {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { auth.signOut() }) {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .navigationDestination(for: UUID.self) { conversationID in
                ChatDetailView(conversationID: conversationID)
            }
            .sheet(isPresented: $showNewChat) {
                newChatSheet
            }
            .task {
                conversationStore.start(userID: userID)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "message")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No conversations yet")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Start a new chat to begin")
                .font(.subheadline)
                .foregroundColor(.tertiary)
        }
    }

    private var listContent: some View {
        List {
            ForEach(conversationStore.conversations) { conversation in
                Button {
                    navigationPath.append(conversation.id)
                } label: {
                    ConversationRow(conversation: conversation)
                }
                .listRowBackground(AppSemanticColors.cardBackground)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task { await conversationStore.deleteConversation(id: conversation.id) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        Task { await conversationStore.archiveConversation(id: conversation.id) }
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                    .tint(.orange)
                }
            }
        }
        .listStyle(.plain)
    }

    private var newChatSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("Type your message…", text: .constant(""), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                    .disabled(true)

                Text("Start typing to begin a conversation")
                    .foregroundColor(.secondary)
                    .padding()

                Spacer()
            }
            .navigationTitle("New Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showNewChat = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(AppSemanticColors.accentColor)
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: "message.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.title)
                    .font(.body)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .foregroundColor(AppSemanticColors.primary)

                Text(conversation.updated_at, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}
