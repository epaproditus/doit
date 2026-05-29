import SwiftUI

struct AddTodoView: View {
    let userID: UUID
    let onCreated: (Todo) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var detail = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("What do you want done?") {
                    TextField("e.g. Email my landlord rent is late", text: $title, axis: .vertical)
                        .lineLimit(1...4)
                }
                Section("Details (optional)") {
                    TextField("Anything the agent should know", text: $detail, axis: .vertical)
                        .lineLimit(1...8)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("New todo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            let todo = try await TodosAPI.create(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                detail: detail.trimmingCharacters(in: .whitespacesAndNewlines),
                userID: userID
            )
            onCreated(todo)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
