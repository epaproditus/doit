import Realtime
import Supabase
import SwiftUI
import UIKit

struct TodoListView: View {
    let userID: UUID

    @State private var todos: [Todo] = []
    @State private var showAddSheet = false
    @State private var showSettings = false
    @State private var selectedSection: TodoListSection = .todo
    @State private var loadError: String?
    @State private var realtimeTask: Task<Void, Never>?

    @Environment(AuthModel.self) private var auth

    var body: some View {
        NavigationStack {
            Group {
                if visibleTodos.isEmpty && loadError == nil {
                    EmptyState(section: selectedSection)
                } else {
                    List {
                        if let loadError {
                            Section { Text(loadError).foregroundStyle(.red) }
                        }
                        ForEach(visibleTodos) { todo in
                            NavigationLink(value: todo) {
                                TodoRow(todo: todo)
                            }
                        }
                        .onDelete(perform: deleteRows)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Todo.self) { TodoDetailView(todo: $0) }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Image("doit_Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 24)
                        .accessibilityLabel("doit")
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomControls
            }
            .sheet(isPresented: $showAddSheet) {
                AddTodoView(userID: userID) { newTodo in
                    todos.insert(newTodo, at: 0)
                    selectedSection = .todo
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .task { await load() }
            .onAppear { startRealtime() }
            .onDisappear { realtimeTask?.cancel() }
            .refreshable { await load() }
        }
    }

    private var visibleTodos: [Todo] {
        switch selectedSection {
        case .todo:
            return todos.filter { $0.status != .done }
        case .done:
            return todos.filter { $0.status == .done }
        }
    }

    private var bottomControls: some View {
        HStack {
            HStack(spacing: 6) {
                dockButton(.todo)
                dockButton(.done)
                Button {
                    playLightHaptic()
                    showSettings = true
                } label: {
                    Image(systemName: "person.crop.circle")
                    .font(.title3.weight(.semibold))
                    .frame(width: 56, height: 56)
                    .foregroundStyle(.secondary)
                    .opacity(0.45)
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .accessibilityLabel("Profile")
            }
            .padding(6)
            .glassEffect(.regular, in: Capsule())

            Spacer()

            Button {
                playLightHaptic()
                showAddSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .frame(width: 60, height: 60)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .glassEffect(.regular, in: Circle())
            .accessibilityLabel("New todo")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 0)
    }

    private func dockButton(_ section: TodoListSection) -> some View {
        Button {
            playLightHaptic()
            selectedSection = section
        } label: {
            Image(systemName: section.symbolName)
            .font(.title3.weight(.semibold))
            .frame(width: 56, height: 56)
            .foregroundStyle(selectedSection == section ? .primary : .secondary)
            .opacity(selectedSection == section ? 1 : 0.45)
            .background {
                if selectedSection == section {
                    Circle().fill(.background.opacity(0.65))
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel(section.title)
    }

    private func playLightHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func load() async {
        do {
            todos = try await TodosAPI.list()
            print("[todos] list loaded count=\(todos.count)")
            loadError = nil
        } catch {
            print("[todos] list load failed: \(error)")
            loadError = "Couldn't load todos: \(error.localizedDescription)"
        }
    }

    private func startRealtime() {
        guard realtimeTask == nil else { return }
        print("[realtime][todos] starting for user=\(userID.uuidString)")
        realtimeTask = Task {
            do {
                let channel = Supa.client.channel("public:todos:user=\(userID.uuidString)")
                let inserts = channel.postgresChange(
                    AnyAction.self,
                    schema: "public",
                    table: "todos"
                )
                await channel.subscribe()
                print("[realtime][todos] subscribed")
                for await change in inserts {
                    print("[realtime][todos] change received: \(change)")
                    await handle(change)
                }
                print("[realtime][todos] stream ended")
            }
        }
    }

    private func handle(_ change: AnyAction) async {
        // Cheapest correct thing: refetch.
        await load()
    }

    private func deleteRows(at offsets: IndexSet) {
        let toDelete = offsets.map { visibleTodos[$0] }
        let idsToDelete = Set(toDelete.map(\.id))
        todos.removeAll { idsToDelete.contains($0.id) }
        Task {
            for t in toDelete {
                try? await TodosAPI.delete(t.id)
            }
        }
    }
}

private enum TodoListSection {
    case todo
    case done

    var title: String {
        switch self {
        case .todo: return "Todo"
        case .done: return "Done"
        }
    }

    var symbolName: String {
        switch self {
        case .todo: return "circle"
        case .done: return "checkmark.circle.fill"
        }
    }
}

private struct TodoRow: View {
    let todo: Todo

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StatusBadge(status: todo.status)
            VStack(alignment: .leading, spacing: 4) {
                Text(todo.title).lineLimit(2)
                if let d = todo.detail, !d.isEmpty {
                    Text(d).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct StatusBadge: View {
    let status: TodoStatus

    var body: some View {
        let (symbol, tint) = symbolAndTint
        Image(systemName: symbol)
            .font(.title3)
            .foregroundStyle(tint)
            .frame(width: 24)
            .symbolEffect(.pulse, isActive: status.isActive)
    }

    private var symbolAndTint: (String, Color) {
        switch status {
        case .todo: return ("circle", .secondary)
        case .requested: return ("hourglass", .blue)
        case .running: return ("sparkles", .blue)
        case .needs_auth: return ("exclamationmark.circle", .orange)
        case .done: return ("checkmark.circle.fill", .green)
        case .failed: return ("xmark.circle.fill", .red)
        case .cancelled: return ("minus.circle", .secondary)
        }
    }
}

private struct EmptyState: View {
    let section: TodoListSection

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text(section == .done ? "Nothing done yet" : "No todos yet")
                .font(.title3.bold())
            Text(section == .done ? "Completed todos will show up here." : "Tap + to add something. Then tap \u{201C}Do it\u{201D} and the agent will take it from there.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
        }
    }
}
