import Foundation

enum TodoStatus: String, Codable, Sendable, CaseIterable {
    case todo
    case requested
    case running
    case needs_auth
    case done
    case failed
    case cancelled

    var label: String {
        switch self {
        case .todo: return "To do"
        case .requested: return "Queued"
        case .running: return "Working..."
        case .needs_auth: return "Needs you"
        case .done: return "Done"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    var isActive: Bool {
        self == .requested || self == .running
    }
}

struct Todo: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let user_id: UUID
    var title: String
    var detail: String?
    var status: TodoStatus
    var hermes_run_id: String?
    var hermes_session_id: String?
    var error_message: String?
    let created_at: Date
    let updated_at: Date
    var completed_at: Date?
}

/// Insert payload for a new todo. The DB fills in `id`, `user_id` (via RLS check),
/// `created_at`, `updated_at`.
struct NewTodo: Encodable, Sendable {
    let user_id: UUID
    let title: String
    let detail: String?
    let status: TodoStatus
}

enum StepKind: String, Codable, Sendable {
    case thought
    case tool_started
    case tool_result
    case oauth_needed
    case final
    case error
}

struct TodoStep: Codable, Identifiable, Hashable, Sendable {
    let id: Int64
    let todo_id: UUID
    let user_id: UUID
    let ts: Date
    let kind: StepKind
    let text: String?
    let url: String?
    let tool_name: String?
}

struct AgentMemory: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let user_id: UUID
    var title: String
    var body: String
    var category: String?
    let created_at: Date
    let updated_at: Date
}

struct NewAgentMemory: Encodable, Sendable {
    let user_id: UUID
    let title: String
    let body: String
    let category: String?
}
