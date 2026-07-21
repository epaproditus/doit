import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class ConversationStore {
    var conversations: [Conversation] = []
    var messagesByConversationID: [UUID: [ConversationMessage]] = [:]
    var loadError: String?
    var isInitialLoading = false
    var isRefreshing = false

    private var activeUserID: UUID?
    private var realtimeStarted = false

    func start(userID: UUID) {
        activeUserID = userID
        guard !realtimeStarted else { return }
        realtimeStarted = true
        Task { await loadConversations() }
    }

    func stop() {
        activeUserID = nil
        realtimeStarted = false
        conversations = []
        messagesByConversationID = [:]
    }

    func loadConversations() async {
        guard let userID = activeUserID else { return }
        isInitialLoading = true
        loadError = nil
        do {
            conversations = try await ConversationsAPI.list()
            isInitialLoading = false
        } catch {
            loadError = error.localizedDescription
            isInitialLoading = false
        }
    }

    func refreshConversation(id: UUID) async {
        do {
            let conv = try await ConversationsAPI.fetch(id)
            if let idx = conversations.firstIndex(where: { $0.id == id }) {
                conversations[idx] = conv
            } else {
                conversations.insert(conv, at: 0)
            }
        } catch {
            print("[ConversationStore] refresh failed for \(id): \(error)")
        }
    }

    func removeConversation(id: UUID) {
        conversations.removeAll { $0.id == id }
        messagesByConversationID.removeValue(forKey: id)
    }

    func createConversation(title: String = "New conversation") async -> Conversation? {
        guard let userID = activeUserID else { return nil }
        do {
            let conv = try await ConversationsAPI.create(userID: userID, title: title)
            conversations.insert(conv, at: 0)
            return conv
        } catch {
            print("[ConversationStore] create failed: \(error)")
            return nil
        }
    }

    func archiveConversation(id: UUID) async {
        do {
            try await ConversationsAPI.archive(id)
            removeConversation(id: id)
        } catch {
            print("[ConversationStore] archive failed for \(id): \(error)")
        }
    }

    func deleteConversation(id: UUID) async {
        do {
            try await ConversationsAPI.delete(id)
            removeConversation(id: id)
        } catch {
            print("[ConversationStore] delete failed for \(id): \(error)")
        }
    }

    func messages(for conversationID: UUID) async -> [ConversationMessage] {
        do {
            return try await ConversationsAPI.messages(for: conversationID)
        } catch {
            print("[ConversationStore] fetch messages failed for \(conversationID): \(error)")
            return []
        }
    }

    func loadMessages(conversationID: UUID) async {
        let msgs = await messages(for: conversationID)
        messagesByConversationID[conversationID] = msgs
    }

    func reloadMessages(conversationID: UUID) async {
        guard messagesByConversationID[conversationID] != nil else { return }
        let msgs = await messages(for: conversationID)
        messagesByConversationID[conversationID] = msgs
    }

    func sendMessage(conversationID: UUID, body: String) async -> ConversationMessage? {
        guard let userID = activeUserID else { return nil }
        do {
            let msg = try await ConversationsAPI.sendMessage(
                conversationID: conversationID,
                userID: userID,
                body: body
            )
            var current = messagesByConversationID[conversationID] ?? []
            current.append(msg)
            messagesByConversationID[conversationID] = current
            return msg
        } catch {
            print("[ConversationStore] sendMessage failed: \(error)")
            return nil
        }
    }
}
