import Foundation

/// One image attached to a todo. The bytes live in the private
/// `todo-attachments` Supabase Storage bucket at `storage_path`; this row
/// is the relational index used by the iOS app and the runner.
struct TodoAttachment: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let todo_id: UUID
    let user_id: UUID
    let storage_path: String
    let mime_type: String
    let width: Int?
    let height: Int?
    let created_at: Date
}

/// Insert payload for a new attachment row. The DB fills in `id` and
/// `created_at`; RLS enforces `user_id == auth.uid()`.
struct NewTodoAttachment: Encodable, Sendable {
    let todo_id: UUID
    let user_id: UUID
    let storage_path: String
    let mime_type: String
    let width: Int?
    let height: Int?
}
