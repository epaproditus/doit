import AuthenticationServices
import PostgREST
import Realtime
import Supabase
import SwiftUI

struct TodoDetailView: View {
    let todo: Todo

    @State private var current: Todo
    @State private var steps: [TodoStep] = []
    @State private var error: String?
    @State private var stepsRealtimeTask: Task<Void, Never>?
    @State private var todoRealtimeTask: Task<Void, Never>?
    @State private var oauthSession: ASWebAuthenticationSession?

    init(todo: Todo) {
        self.todo = todo
        self._current = State(initialValue: todo)
    }

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    StatusBadge(status: current.status)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(current.title).font(.title3.weight(.semibold))
                        if let d = current.detail, !d.isEmpty {
                            Text(d).font(.body).foregroundStyle(.secondary)
                        }
                        Text(current.status.label)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                ActionButtons(
                    status: current.status,
                    onDoIt: doIt,
                    onStop: stop
                )
            }

            if current.status == .needs_auth, let url = mostRecentOAuthURL() {
                Section("Connect to continue") {
                    Button {
                        startOAuth(url: url)
                    } label: {
                        Label("Connect your account", systemImage: "key.fill")
                    }
                }
            }

            if !steps.isEmpty {
                Section("Activity") {
                    ForEach(steps) { step in
                        StepRow(step: step) { url in
                            startOAuth(url: url)
                        }
                    }
                }
            }

            if let err = current.error_message ?? error {
                Section { Text(err).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Todo")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadSteps()
            startStepsRealtime()
            startTodoRealtime()
        }
        .onDisappear {
            stepsRealtimeTask?.cancel()
            todoRealtimeTask?.cancel()
        }
    }

    // MARK: - Actions

    private func doIt() {
        Task {
            do {
                print("[todo-detail] requesting todo id=\(current.id)")
                try await TodosAPI.setStatus(current.id, .requested)
                current.status = .requested
                print("[todo-detail] local status set to requested id=\(current.id)")
            } catch {
                print("[todo-detail] request failed id=\(current.id): \(error)")
                self.error = error.localizedDescription
            }
        }
    }

    private func stop() {
        Task {
            do {
                try await TodosAPI.setStatus(current.id, .cancelled)
                current.status = .cancelled
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func mostRecentOAuthURL() -> URL? {
        for s in steps.reversed() {
            if s.kind == .oauth_needed, let urlStr = s.url, let url = URL(string: urlStr) {
                return url
            }
        }
        return nil
    }

    private func startOAuth(url: URL) {
        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: nil
        ) { _, _ in
            // The user finishes in the browser; Composio holds the tokens.
            // They can re-tap "Do it" to resume.
        }
        session.prefersEphemeralWebBrowserSession = false
        session.presentationContextProvider = PresentationContextProvider.shared
        oauthSession = session
        session.start()
    }

    // MARK: - Loading + realtime

    private func loadSteps() async {
        do {
            steps = try await TodosAPI.steps(for: current.id)
            print("[realtime][steps] loaded count=\(steps.count) todo=\(current.id)")
        } catch {
            print("[realtime][steps] load failed todo=\(current.id): \(error)")
            self.error = "Couldn't load steps: \(error.localizedDescription)"
        }
    }

    private func startStepsRealtime() {
        guard stepsRealtimeTask == nil else { return }
        print("[realtime][steps] starting todo=\(current.id)")
        stepsRealtimeTask = Task {
            let channel = Supa.client.channel("steps:\(current.id.uuidString)")
            let stream = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "todo_steps",
                filter: "todo_id=eq.\(current.id.uuidString)"
            )
            await channel.subscribe()
            print("[realtime][steps] subscribed todo=\(current.id)")
            for await change in stream {
                print("[realtime][steps] change received todo=\(current.id): \(change)")
                await loadSteps()
            }
            print("[realtime][steps] stream ended todo=\(current.id)")
        }
    }

    private func startTodoRealtime() {
        guard todoRealtimeTask == nil else { return }
        print("[realtime][todo] starting todo=\(current.id)")
        todoRealtimeTask = Task {
            let channel = Supa.client.channel("todo:\(current.id.uuidString)")
            let stream = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "todos",
                filter: "id=eq.\(current.id.uuidString)"
            )
            await channel.subscribe()
            print("[realtime][todo] subscribed todo=\(current.id)")
            for await change in stream {
                print("[realtime][todo] change received todo=\(current.id): \(change)")
                await refreshTodo()
            }
            print("[realtime][todo] stream ended todo=\(current.id)")
        }
    }

    private func refreshTodo() async {
        do {
            let rows: [Todo] = try await Supa.client
                .from("todos")
                .select()
                .eq("id", value: current.id)
                .limit(1)
                .execute()
                .value
            if let first = rows.first {
                self.current = first
                print("[realtime][todo] refreshed id=\(first.id) status=\(first.status)")
            } else {
                print("[realtime][todo] refresh returned no rows id=\(current.id)")
            }
        } catch {
            print("[realtime][todo] refresh failed id=\(current.id): \(error)")
        }
    }
}

private struct ActionButtons: View {
    let status: TodoStatus
    let onDoIt: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack {
            if status.isActive {
                Button(role: .destructive, action: onStop) {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
            } else if status == .done || status == .failed || status == .cancelled {
                Button(action: onDoIt) {
                    Label("Run again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(action: onDoIt) {
                    Label("Do it", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct StepRow: View {
    let step: TodoStep
    let openURL: (URL) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                if let toolName = step.tool_name, !toolName.isEmpty {
                    Text(prettify(toolName))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if let text = step.text, !text.isEmpty {
                    Text(text)
                        .font(.body)
                        .textSelection(.enabled)
                }
                if step.kind == .oauth_needed,
                   let urlStr = step.url,
                   let url = URL(string: urlStr) {
                    Button("Open authorization link") {
                        openURL(url)
                    }
                    .font(.footnote)
                }
                Text(step.ts.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var symbol: String {
        switch step.kind {
        case .thought: return "bubble.left"
        case .tool_started: return "gearshape.2"
        case .tool_result: return "checkmark"
        case .oauth_needed: return "key.fill"
        case .final: return "checkmark.seal.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch step.kind {
        case .thought: return .secondary
        case .tool_started: return .blue
        case .tool_result: return .green
        case .oauth_needed: return .orange
        case .final: return .green
        case .error: return .red
        }
    }

    private func prettify(_ name: String) -> String {
        name
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "mcp ", with: "")
            .capitalized
    }
}

/// ASWebAuthenticationSession needs a window to anchor on.
@MainActor
final class PresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = PresentationContextProvider()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
    }
}
