import SwiftUI

struct MemoryView: View {
    @Environment(AuthModel.self) private var auth

    @State private var memories: [AgentMemory] = []
    @State private var loading = true
    @State private var error: String?
    @State private var showAddSheet = false

    var body: some View {
        List {
            Section {
                Text("Add things like family relationships, preferred email addresses, writing preferences, and recurring context. The runner shares these visible memories with Hermes when it works on your todos.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if loading && memories.isEmpty {
                Section { ProgressView() }
            }

            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }

            if memories.isEmpty && !loading {
                Section {
                    ContentUnavailableView(
                        "No memories yet",
                        systemImage: "brain.head.profile",
                        description: Text("Tap + to teach the agent something it should remember.")
                    )
                }
            } else {
                Section {
                    ForEach(memories) { memory in
                        NavigationLink {
                            MemoryEditorView(existing: memory) { updated in
                                await save(memory, draft: updated)
                            }
                        } label: {
                            MemoryRow(memory: memory)
                        }
                    }
                    .onDelete(perform: deleteRows)
                }
            }
        }
        .navigationTitle("Memory")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add memory")
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showAddSheet) {
            NavigationStack {
                MemoryEditorView(existing: nil) { draft in
                    await create(draft)
                    showAddSheet = false
                }
            }
        }
    }

    private var userID: UUID? {
        if case .signedIn(let userID) = auth.state {
            return userID
        }
        return nil
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            memories = try await MemoriesAPI.list()
            error = nil
        } catch {
            self.error = "Couldn't load memories: \(error.localizedDescription)"
        }
    }

    private func create(_ draft: MemoryDraft) async {
        guard let userID else { return }
        do {
            let memory = try await MemoriesAPI.create(
                title: draft.title,
                body: draft.body,
                category: draft.category,
                userID: userID
            )
            memories.insert(memory, at: 0)
            error = nil
        } catch {
            self.error = "Couldn't save memory: \(error.localizedDescription)"
        }
    }

    private func save(_ memory: AgentMemory, draft: MemoryDraft) async {
        do {
            var updated = memory
            updated.title = draft.title
            updated.body = draft.body
            updated.category = draft.category.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            try await MemoriesAPI.update(updated)
            await load()
        } catch {
            self.error = "Couldn't update memory: \(error.localizedDescription)"
        }
    }

    private func deleteRows(at offsets: IndexSet) {
        let toDelete = offsets.map { memories[$0] }
        memories.remove(atOffsets: offsets)
        Task {
            for memory in toDelete {
                try? await MemoriesAPI.delete(memory.id)
            }
        }
    }
}

private struct MemoryRow: View {
    let memory: AgentMemory

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(memory.title)
                    .font(.headline)
                if let category = memory.category, !category.isEmpty {
                    Text(category)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                        .foregroundStyle(.blue)
                }
            }
            Text(memory.body)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(.vertical, 4)
    }
}

struct MemoryDraft {
    var title: String
    var body: String
    var category: String
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private struct MemoryEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let existing: AgentMemory?
    let onSave: (MemoryDraft) async -> Void

    @State private var title: String
    @State private var bodyText: String
    @State private var category: String
    @State private var saving = false

    init(existing: AgentMemory?, onSave: @escaping (MemoryDraft) async -> Void) {
        self.existing = existing
        self.onSave = onSave
        _title = State(initialValue: existing?.title ?? "")
        _bodyText = State(initialValue: existing?.body ?? "")
        _category = State(initialValue: existing?.category ?? "")
    }

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $title)
                TextField("Category", text: $category)
                    .textInputAutocapitalization(.words)
            }
            Section("What should the agent remember?") {
                TextEditor(text: $bodyText)
                    .frame(minHeight: 140)
            }
        }
        .navigationTitle(existing == nil ? "Add Memory" : "Edit Memory")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .disabled(saving)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(saving ? "Saving..." : "Save") {
                    Task { await save() }
                }
                .disabled(!canSave || saving)
            }
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() async {
        saving = true
        defer { saving = false }
        await onSave(
            MemoryDraft(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                body: bodyText.trimmingCharacters(in: .whitespacesAndNewlines),
                category: category.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        )
        dismiss()
    }
}
