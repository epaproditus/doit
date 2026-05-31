import AuthenticationServices
import PhotosUI
import PostgREST
import Realtime
import Supabase
import SwiftUI

struct TodoDetailView: View {
    /// Hard cap on attached images per task; matches the New Task sheet.
    private static let maxAttachments = 5

    let todo: Todo

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var current: Todo
    @State private var steps: [TodoStep] = []
    @State private var interaction: TodoInteraction?
    @State private var artifacts: [TodoArtifact] = []
    @State private var submittingOptionID: String?
    @State private var error: String?
    @State private var stepsRealtimeTask: Task<Void, Never>?
    @State private var todoRealtimeTask: Task<Void, Never>?
    @State private var interactionsRealtimeTask: Task<Void, Never>?
    @State private var artifactsRealtimeTask: Task<Void, Never>?
    @State private var oauthSession: ASWebAuthenticationSession?
    @State private var attachments: [TodoAttachment] = []
    @State private var attachmentURLs: [UUID: URL] = [:]
    @State private var messages: [TodoMessage] = []
    @State private var photoSelections: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var preview: AttachmentPreview?
    @State private var uploading = false
    @State private var sending = false

    /// Split between the task header and chat thread. The thread gets the
    /// majority of the screen by default; the user can drag, mini, or full
    /// either side via the split's drag pill.
    @State private var splitDetent: SplitDetent = .fraction(0.3)

    init(todo: Todo) {
        self.todo = todo
        self._current = State(initialValue: todo)
    }

    var body: some View {
        VerticalSplit(
            detent: $splitDetent,
            topTitle: current.title.isEmpty ? "Task" : current.title,
            bottomTitle: "Chat",
            topView: {
                TaskHeaderView(
                    todo: current,
                    artifacts: artifacts,
                    onBack: { dismiss() },
                    onDelete: deleteTask
                )
            },
            bottomView: {
                TodoChatThread(
                    items: conversationItems,
                    attachmentsByID: attachmentsByID,
                    attachmentURLs: attachmentURLs,
                    submittingOptionID: submittingOptionID,
                    isAgentRunning: current.status.isActive || sending,
                    photoSelections: $photoSelections,
                    canAddMoreAttachments: canAddMoreAttachments,
                    maxNewAttachments: max(1, TodoDetailView.maxAttachments - attachments.count),
                    onTakePhoto: takePhoto,
                    onRemoveAttachment: { attachment in
                        Task { await delete(attachment) }
                    },
                    onPreviewAttachment: { attachment in
                        if let url = attachmentURLs[attachment.id] {
                            preview = AttachmentPreview(url: url)
                        }
                    },
                    onOpenOAuth: { url in startOAuth(url: url) },
                    onRespondInteraction: { interaction, optionID, text in
                        Task {
                            await respond(
                                interaction: interaction,
                                optionID: optionID,
                                text: text
                            )
                        }
                    },
                    onSend: { text in
                        Task { await send(text) }
                    }
                )
            }
        )
        .handleTrailingText(formattedTokens(current.total_tokens))
        .toolbar(.hidden, for: .navigationBar)
        .task {
            // Refetch the row on every appearance so columns that mutate
            // mid-run (status, total_tokens, error_message) are fresh —
            // the list view's cached `Todo` can lag, especially after the
            // user navigates back here from the home feed once a run has
            // already incremented tokens.
            await refreshTodo()
            await loadSteps()
            await loadInteraction()
            await loadAttachments()
            await loadArtifacts()
            await loadMessages()
            startStepsRealtime()
            startTodoRealtime()
            startInteractionsRealtime()
            startArtifactsRealtime()
        }
        .onDisappear {
            print("[detail] onDisappear todo=\(current.id)")
            stopRealtime()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            print("[detail] scenePhase \(oldPhase)→\(newPhase) todo=\(current.id)")
            // Backgrounding the app can drop the websocket; on
            // foreground, force-rebuild every realtime subscription and
            // refetch state so the detail sheet doesn't sit on stale
            // status / steps / interactions from before the switch.
            guard newPhase == .active else { return }
            stopRealtime()
            startStepsRealtime()
            startTodoRealtime()
            startInteractionsRealtime()
            startArtifactsRealtime()
            Task {
                await refreshTodo()
                await loadSteps()
                await loadInteraction()
                await loadArtifacts()
                await loadMessages()
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(
                onPicked: { image in
                    showCamera = false
                    Task { await uploadCapturedImage(image) }
                },
                onCancel: { showCamera = false }
            )
            .ignoresSafeArea()
        }
        .sheet(item: $preview) { item in
            AttachmentPreviewScreen(url: item.url) { preview = nil }
        }
        .onChange(of: photoSelections) { _, selections in
            guard !selections.isEmpty else { return }
            Task { await uploadPickedImages(selections) }
        }
    }

    // MARK: - Derived chat data

    private var attachmentsByID: [UUID: TodoAttachment] {
        Dictionary(uniqueKeysWithValues: attachments.map { ($0.id, $0) })
    }

    private var conversationItems: [ConversationItem] {
        ConversationBuilder.build(
            todo: current,
            steps: steps,
            interaction: interaction,
            attachments: attachments,
            messages: messages,
            error: current.error_message ?? error
        )
    }

    private var canAddMoreAttachments: Bool {
        attachments.count < TodoDetailView.maxAttachments
    }

    /// Compact token count rendered in the drag pill. Hides while the todo
    /// has never run (`nil` or 0) so users don't see "0 tok" on fresh
    /// items. Uses the system locale's compact notation for big numbers,
    /// e.g. `12K tok`, `1.2M tok`.
    private func formattedTokens(_ value: Int64?) -> String? {
        guard let v = value, v > 0 else { return nil }
        if v < 1_000 { return "\(v) tok" }
        let formatted = v.formatted(
            .number
                .notation(.compactName)
                .precision(.fractionLength(0...1))
        )
        return "\(formatted) tok"
    }

    // MARK: - Actions

    private func takePhoto() {
        #if targetEnvironment(simulator)
        self.error = "Camera isn't available on the simulator."
        #else
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            showCamera = true
        } else {
            self.error = "Camera isn't available on this device."
        }
        #endif
    }

    /// Permanent removal of the todo (and its cascaded children). Pops back
    /// to the list immediately so the navigation animation runs in parallel
    /// with the network round-trip — the row is already gone client-side
    /// via realtime by the time the list view re-renders.
    private func deleteTask() {
        let id = current.id
        dismiss()
        Task {
            try? await TodosAPI.delete(id)
        }
    }

    private func respond(
        interaction: TodoInteraction,
        optionID: String?,
        text: String?
    ) async {
        submittingOptionID = optionID ?? "__freeform"
        defer { submittingOptionID = nil }
        let phase: InteractionPhase = interaction.isPreparationPhase ? .prepare : .execute
        do {
            try await TodosAPI.respond(
                to: interaction.id,
                todoID: current.id,
                optionID: optionID,
                text: text,
                phase: phase
            )
            // Optimistic: hide the card immediately. Realtime will refresh
            // shortly.
            self.interaction = nil
            if optionID?.lowercased() == "cancel" {
                current.status = .cancelled
            } else {
                current.status = phase.nextStatus
            }
        } catch {
            print("[interaction] respond failed: \(error)")
            self.error = "Couldn't send your response: \(error.localizedDescription)"
        }
    }

    /// Free-form chat send from the composer. If there's an open
    /// interaction card we route the typed text as the freeform answer to
    /// that card (so a single round-trip both closes the card and resumes
    /// the agent). Otherwise we insert a `todo_messages` row, which the
    /// runner picks up on its next claim. The optimistic local append
    /// makes the bubble appear instantly; realtime will reconcile the row
    /// id once the server returns.
    private func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !sending else { return }
        sending = true
        defer { sending = false }

        if let open = interaction, open.status == .open {
            await respond(interaction: open, optionID: nil, text: trimmed)
            return
        }

        // Optimistic local bubble keyed by a temporary UUID so the chat
        // doesn't feel laggy while the insert + status flip resolves.
        let optimistic = TodoMessage(
            id: UUID(),
            todo_id: current.id,
            user_id: current.user_id,
            body: trimmed,
            consumed_at: nil,
            created_at: Date()
        )
        messages.append(optimistic)
        let priorStatus = current.status
        current.status = .requested

        do {
            let saved = try await TodosAPI.sendMessage(
                todoID: current.id,
                userID: current.user_id,
                body: trimmed
            )
            // Swap the optimistic row for the real one so realtime
            // refreshes don't append a second copy on top of ours.
            if let idx = messages.firstIndex(where: { $0.id == optimistic.id }) {
                messages[idx] = saved
            } else {
                messages.append(saved)
            }
        } catch {
            print("[chat] send failed: \(error)")
            messages.removeAll { $0.id == optimistic.id }
            current.status = priorStatus
            self.error = "Couldn't send your message: \(error.localizedDescription)"
        }
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
        let prevCount = steps.count
        let prevLastID = steps.last?.id
        do {
            steps = try await TodosAPI.steps(for: current.id)
            let lastKind = steps.last?.kind.rawValue ?? "-"
            let lastID = steps.last?.id
            let added = steps.count - prevCount
            let changed = added != 0 || lastID != prevLastID
            print("[realtime][steps] loaded count=\(steps.count) (Δ=\(added)) lastKind=\(lastKind) changed=\(changed) todo=\(current.id)")
            if steps.contains(where: \.containsInteractionMarker) {
                await loadInteractionWithRetry()
            }
        } catch {
            print("[realtime][steps] load failed todo=\(current.id): \(error)")
            self.error = "Couldn't load steps: \(error.localizedDescription)"
        }
    }

    private func loadInteraction() async {
        let prevID = interaction?.id
        do {
            interaction = try await TodosAPI.openInteraction(for: current.id)
            let newID = interaction?.id
            let changed = prevID != newID
            print("[interaction] loaded id=\(newID?.uuidString ?? "nil") prev=\(prevID?.uuidString ?? "nil") changed=\(changed) todo=\(current.id)")
        } catch {
            print("[interaction] load failed todo=\(current.id): \(error)")
        }
    }

    private func startStepsRealtime() {
        guard stepsRealtimeTask == nil else { return }
        print("[realtime][steps] starting todo=\(current.id)")
        let todoID = current.id
        stepsRealtimeTask = Task {
            var attempt = 0
            // Retry loop so a websocket drop (background, network blip)
            // doesn't permanently kill the live step stream.
            while !Task.isCancelled {
                attempt += 1
                let channel = Supa.client.channel("steps:\(todoID.uuidString)")
                let stream = channel.postgresChange(
                    AnyAction.self,
                    schema: "public",
                    table: "todo_steps",
                    filter: "todo_id=eq.\(todoID.uuidString)"
                )
                do {
                    try await channel.subscribeWithError()
                    print("[realtime][steps] subscribe ok status=\(channel.status) todo=\(todoID) attempt=\(attempt)")
                } catch {
                    print("[realtime][steps] subscribe FAILED status=\(channel.status) error=\(error) todo=\(todoID) attempt=\(attempt)")
                }
                var eventCount = 0
                for await change in stream {
                    if Task.isCancelled { break }
                    eventCount += 1
                    print("[realtime][steps] event #\(eventCount) todo=\(todoID): \(change)")
                    await loadSteps()
                }
                // `removeChannel` (not `unsubscribe`) evicts the channel
                // from the realtime client's topic cache so the next
                // retry-loop iteration can create a fresh subscription.
                await Supa.client.removeChannel(channel)
                print("[realtime][steps] stream ended todo=\(todoID) events=\(eventCount) cancelled=\(Task.isCancelled)")
                if Task.isCancelled { break }
                try? await Task.sleep(for: .seconds(1))
            }
            print("[realtime][steps] task exit todo=\(todoID)")
        }
    }

    private func startTodoRealtime() {
        guard todoRealtimeTask == nil else { return }
        print("[realtime][todo] starting todo=\(current.id)")
        let todoID = current.id
        todoRealtimeTask = Task {
            var attempt = 0
            while !Task.isCancelled {
                attempt += 1
                let channel = Supa.client.channel("todo:\(todoID.uuidString)")
                let stream = channel.postgresChange(
                    AnyAction.self,
                    schema: "public",
                    table: "todos",
                    filter: "id=eq.\(todoID.uuidString)"
                )
                do {
                    try await channel.subscribeWithError()
                    print("[realtime][todo] subscribe ok status=\(channel.status) todo=\(todoID) attempt=\(attempt)")
                } catch {
                    print("[realtime][todo] subscribe FAILED status=\(channel.status) error=\(error) todo=\(todoID) attempt=\(attempt)")
                }
                var eventCount = 0
                for await change in stream {
                    if Task.isCancelled { break }
                    eventCount += 1
                    print("[realtime][todo] event #\(eventCount) todo=\(todoID): \(change)")
                    await refreshTodo()
                }
                await Supa.client.removeChannel(channel)
                print("[realtime][todo] stream ended todo=\(todoID) events=\(eventCount) cancelled=\(Task.isCancelled)")
                if Task.isCancelled { break }
                try? await Task.sleep(for: .seconds(1))
            }
            print("[realtime][todo] task exit todo=\(todoID)")
        }
    }

    private func startInteractionsRealtime() {
        guard interactionsRealtimeTask == nil else { return }
        print("[realtime][interactions] starting todo=\(current.id)")
        let todoID = current.id
        interactionsRealtimeTask = Task {
            var attempt = 0
            while !Task.isCancelled {
                attempt += 1
                let channel = Supa.client.channel("interactions:\(todoID.uuidString)")
                let stream = channel.postgresChange(
                    AnyAction.self,
                    schema: "public",
                    table: "todo_interactions",
                    filter: "todo_id=eq.\(todoID.uuidString)"
                )
                do {
                    try await channel.subscribeWithError()
                    print("[realtime][interactions] subscribe ok status=\(channel.status) todo=\(todoID) attempt=\(attempt)")
                } catch {
                    print("[realtime][interactions] subscribe FAILED status=\(channel.status) error=\(error) todo=\(todoID) attempt=\(attempt)")
                }
                var eventCount = 0
                for await change in stream {
                    if Task.isCancelled { break }
                    eventCount += 1
                    print("[realtime][interactions] event #\(eventCount) todo=\(todoID): \(change)")
                    await loadInteraction()
                }
                await Supa.client.removeChannel(channel)
                print("[realtime][interactions] stream ended todo=\(todoID) events=\(eventCount) cancelled=\(Task.isCancelled)")
                if Task.isCancelled { break }
                try? await Task.sleep(for: .seconds(1))
            }
            print("[realtime][interactions] task exit todo=\(todoID)")
        }
    }

    private func startArtifactsRealtime() {
        guard artifactsRealtimeTask == nil else { return }
        print("[realtime][artifacts] starting todo=\(current.id)")
        let todoID = current.id
        artifactsRealtimeTask = Task {
            var attempt = 0
            while !Task.isCancelled {
                attempt += 1
                let channel = Supa.client.channel("artifacts:\(todoID.uuidString)")
                let stream = channel.postgresChange(
                    AnyAction.self,
                    schema: "public",
                    table: "todo_artifacts",
                    filter: "todo_id=eq.\(todoID.uuidString)"
                )
                do {
                    try await channel.subscribeWithError()
                    print("[realtime][artifacts] subscribe ok status=\(channel.status) todo=\(todoID) attempt=\(attempt)")
                } catch {
                    print("[realtime][artifacts] subscribe FAILED status=\(channel.status) error=\(error) todo=\(todoID) attempt=\(attempt)")
                }
                var eventCount = 0
                for await change in stream {
                    if Task.isCancelled { break }
                    eventCount += 1
                    print("[realtime][artifacts] event #\(eventCount) todo=\(todoID): \(change)")
                    await loadArtifacts()
                }
                await Supa.client.removeChannel(channel)
                print("[realtime][artifacts] stream ended todo=\(todoID) events=\(eventCount) cancelled=\(Task.isCancelled)")
                if Task.isCancelled { break }
                try? await Task.sleep(for: .seconds(1))
            }
            print("[realtime][artifacts] task exit todo=\(todoID)")
        }
    }

    /// Cancel every realtime task and clear its handle. Without nil-ing
    /// out the State the `guard … == nil` short-circuits next time
    /// `start…Realtime()` is called (e.g. when the user comes back to
    /// foreground), and the detail view sits without live updates until
    /// it's torn down and re-created.
    private func stopRealtime() {
        stepsRealtimeTask?.cancel()
        stepsRealtimeTask = nil
        todoRealtimeTask?.cancel()
        todoRealtimeTask = nil
        interactionsRealtimeTask?.cancel()
        interactionsRealtimeTask = nil
        artifactsRealtimeTask?.cancel()
        artifactsRealtimeTask = nil
    }

    private func refreshTodo() async {
        let prevStatus = current.status
        let prevTokens = current.total_tokens ?? 0
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
                let newTokens = first.total_tokens ?? 0
                let changed = (prevStatus != first.status) || (prevTokens != newTokens)
                print("[realtime][todo] refreshed id=\(first.id) status=\(prevStatus)→\(first.status) tok=\(prevTokens)→\(newTokens) changed=\(changed)")
                if first.status == .needs_input {
                    await loadInteractionWithRetry()
                }
            } else {
                print("[realtime][todo] refresh returned no rows id=\(current.id)")
            }
        } catch {
            print("[realtime][todo] refresh failed id=\(current.id): \(error)")
        }
    }

    private func loadInteractionWithRetry() async {
        await loadInteraction()
        if interaction == nil {
            try? await Task.sleep(for: .milliseconds(500))
            await loadInteraction()
        }
    }

    // MARK: - Artifacts

    private func loadArtifacts() async {
        do {
            let rows = try await TodosAPI.artifacts(for: current.id)
            // Drop empty/malformed rows defensively so the header view
            // never tries to render a card with no content.
            artifacts = rows.filter(\.hasContent)
            print("[artifacts] loaded count=\(artifacts.count) todo=\(current.id)")
        } catch {
            print("[artifacts] load failed todo=\(current.id): \(error)")
        }
    }

    // MARK: - Messages

    private func loadMessages() async {
        do {
            let fresh = try await TodosAPI.messages(for: current.id)
            // Preserve any optimistic locals we inserted but the server
            // hasn't echoed back yet (shouldn't happen often since the
            // insert API returns the persisted row, but guard against
            // races on the scenePhase refresh path).
            let knownIDs = Set(fresh.map(\.id))
            let pending = messages.filter { !knownIDs.contains($0.id) && $0.consumed_at == nil }
            messages = fresh + pending
            print("[chat] messages loaded count=\(messages.count) todo=\(current.id)")
        } catch {
            print("[chat] messages load failed todo=\(current.id): \(error)")
        }
    }

    // MARK: - Attachments

    private func loadAttachments() async {
        do {
            attachments = try await AttachmentsAPI.list(forTodoID: current.id)
            await refreshAttachmentURLs()
        } catch {
            print("[attachments] load failed todo=\(current.id): \(error)")
        }
    }

    private func refreshAttachmentURLs() async {
        var resolved: [UUID: URL] = [:]
        for attachment in attachments {
            do {
                let url = try await AttachmentsAPI.signedURL(for: attachment)
                resolved[attachment.id] = url
            } catch {
                print("[attachments] sign failed id=\(attachment.id): \(error)")
            }
        }
        attachmentURLs = resolved
    }

    private func uploadCapturedImage(_ image: UIImage) async {
        await uploadImages([image])
    }

    private func uploadPickedImages(_ selections: [PhotosPickerItem]) async {
        let remainingSlots = TodoDetailView.maxAttachments - attachments.count
        let slice = Array(selections.prefix(max(0, remainingSlots)))
        var images: [UIImage] = []
        for item in slice {
            do {
                if let data = try await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    images.append(image)
                }
            } catch {
                self.error = "Couldn't load that photo."
            }
        }
        photoSelections = []
        if !images.isEmpty {
            await uploadImages(images)
        }
    }

    private func uploadImages(_ images: [UIImage]) async {
        guard !images.isEmpty else { return }
        uploading = true
        defer { uploading = false }
        var failures = 0
        for image in images {
            do {
                let attachment = try await AttachmentsAPI.upload(
                    image: image,
                    todoID: current.id,
                    userID: current.user_id
                )
                attachments.append(attachment)
                if let url = try? await AttachmentsAPI.signedURL(for: attachment) {
                    attachmentURLs[attachment.id] = url
                }
            } catch {
                failures += 1
            }
        }
        if failures > 0 {
            self.error = failures == 1
                ? "1 image failed to upload."
                : "\(failures) images failed to upload."
        }
    }

    private func delete(_ attachment: TodoAttachment) async {
        do {
            try await AttachmentsAPI.delete(attachment)
            attachments.removeAll { $0.id == attachment.id }
            attachmentURLs.removeValue(forKey: attachment.id)
        } catch {
            self.error = "Couldn't delete that image: \(error.localizedDescription)"
        }
    }
}

private struct AttachmentPreview: Identifiable {
    let id = UUID()
    let url: URL
}

private struct AttachmentPreviewScreen: View {
    let url: URL
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                case .failure:
                    Text("Couldn't load this image.")
                        .foregroundStyle(.white)
                default:
                    ProgressView().tint(.white)
                }
            }
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.black.opacity(0.6), in: Circle())
            }
            .buttonStyle(.plain)
            .padding()
            .accessibilityLabel("Close preview")
        }
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
