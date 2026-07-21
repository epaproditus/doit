import Foundation

struct Conversation: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let user_id: UUID
    var title: String
    var status: String
    var hermes_session_id: String?
    var hermes_run_id: String?
    let created_at: Date
    var updated_at: Date
    var archived_at: Date?
}

struct NewConversation: Encodable, Sendable {
    let user_id: UUID
    let title: String
}

struct ConversationMessage: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let conversation_id: UUID
    let user_id: UUID
    var role: String
    var body: String
    var payload: JSONValue?
    let created_at: Date
}

struct NewConversationMessage: Encodable, Sendable {
    let conversation_id: UUID
    let user_id: UUID
    let body: String
}

struct ConversationPatch: Encodable, Sendable {
    let title: String?
    let status: String?

    init(title: String? = nil, status: String? = nil) {
        self.title = title
        self.status = status
    }
}
