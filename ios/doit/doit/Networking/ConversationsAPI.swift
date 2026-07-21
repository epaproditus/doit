import Foundation
import Supabase

@MainActor
enum ConversationsAPI {
    static func list() async throws -> [Conversation] {
        try await Supa.client
            .from("conversations")
            .select()
            .eq("status", value: "active")
            .order("updated_at", ascending: false)
            .execute()
            .value
    }

    static func fetch(_ id: UUID) async throws -> Conversation {
        let rows: [Conversation] = try await Supa.client
            .from("conversations")
            .select()
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value
        guard let conv = rows.first else { throw ConversationsAPIError.notFound }
        return conv
    }

    static func create(userID: UUID, title: String = "New conversation") async throws -> Conversation {
        let row = NewConversation(user_id: userID, title: title)
        let rows: [Conversation] = try await Supa.client
            .from("conversations")
            .insert(row)
            .select()
            .execute()
            .value
        guard let conv = rows.first else { throw ConversationsAPIError.empty }
        return conv
    }

    static func update(_ id: UUID, title: String? = nil, status: String? = nil) async throws {
        let patch = ConversationPatch(title: title, status: status)
        try await Supa.client
            .from("conversations")
            .update(patch)
            .eq("id", value: id)
            .execute()
    }

    static func archive(_ id: UUID) async throws {
        try await update(id, status: "archived")
    }

    static func delete(_ id: UUID) async throws {
        _ = try await Supa.client
            .from("conversations")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    static func messages(for conversationID: UUID) async throws -> [ConversationMessage] {
        try await Supa.client
            .from("conversation_messages")
            .select()
            .eq("conversation_id", value: conversationID)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    static func sendMessage(conversationID: UUID, userID: UUID, body: String) async throws -> ConversationMessage {
        let row = NewConversationMessage(
            conversation_id: conversationID,
            user_id: userID,
            body: body
        )
        let rows: [ConversationMessage] = try await Supa.client
            .from("conversation_messages")
            .insert(row)
            .select()
            .execute()
            .value
        guard let msg = rows.first else { throw ConversationsAPIError.empty }
        return msg
    }
}

enum ConversationsAPIError: Error {
    case notFound
    case empty
}
