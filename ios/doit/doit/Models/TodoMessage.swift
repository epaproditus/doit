import Foundation

/// One free-form chat message the user typed to the agent for this todo.
/// Inserted by the iOS app from the detail view composer; the runner stamps
/// `consumed_at` once it has folded the body into a Hermes prompt so the
/// next resume doesn't replay the same message.
struct TodoMessage: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let todo_id: UUID
    let user_id: UUID
    let body: String
    let consumed_at: Date?
    let created_at: Date
}

/// Insert payload for a new user chat message. The DB fills in `id` and
/// `created_at`; `consumed_at` stays null until the runner picks it up.
/// RLS enforces `user_id == auth.uid()`.
struct NewTodoMessage: Encodable, Sendable {
    let todo_id: UUID
    let user_id: UUID
    let body: String
}
