import Foundation
import Supabase

@MainActor
enum TodosAPI {
    static func list() async throws -> [Todo] {
        try await Supa.client
            .from("todos")
            .select()
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    static func create(title: String, detail: String?, userID: UUID) async throws -> Todo {
        let row = NewTodo(
            user_id: userID,
            title: title,
            detail: (detail?.isEmpty ?? true) ? nil : detail,
            status: .todo
        )
        let result: [Todo] = try await Supa.client
            .from("todos")
            .insert(row)
            .select()
            .execute()
            .value
        guard let todo = result.first else { throw TodosAPIError.empty }
        return todo
    }

    static func setStatus(_ id: UUID, _ status: TodoStatus) async throws {
        struct Patch: Encodable { let status: String }
        _ = try await Supa.client
            .from("todos")
            .update(Patch(status: status.rawValue))
            .eq("id", value: id)
            .execute()
    }

    static func update(_ id: UUID, title: String, detail: String?) async throws {
        struct Patch: Encodable { let title: String; let detail: String? }
        _ = try await Supa.client
            .from("todos")
            .update(Patch(title: title, detail: (detail?.isEmpty ?? true) ? nil : detail))
            .eq("id", value: id)
            .execute()
    }

    static func delete(_ id: UUID) async throws {
        _ = try await Supa.client
            .from("todos")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    static func steps(for todoID: UUID) async throws -> [TodoStep] {
        try await Supa.client
            .from("todo_steps")
            .select()
            .eq("todo_id", value: todoID)
            .order("ts", ascending: true)
            .execute()
            .value
    }
}

enum TodosAPIError: Error {
    case empty
}
