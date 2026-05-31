import PhotosUI
import SwiftUI

/// Bottom panel of the split-screen detail view: a scrolling conversation
/// of `ConversationItem`s plus a live composer. Free-form sends go through
/// `onSend`; the composer disables itself while the agent is active so the
/// user can't queue messages on top of an in-flight Hermes turn.
struct TodoChatThread: View {
    let items: [ConversationItem]
    let attachmentsByID: [UUID: TodoAttachment]
    let attachmentURLs: [UUID: URL]
    let submittingOptionID: String?
    let isAgentRunning: Bool

    @Binding var photoSelections: [PhotosPickerItem]
    let canAddMoreAttachments: Bool
    let maxNewAttachments: Int
    let onTakePhoto: () -> Void
    let onRemoveAttachment: (TodoAttachment) -> Void
    let onPreviewAttachment: (TodoAttachment) -> Void
    let onOpenOAuth: (URL) -> Void
    let onRespondInteraction: (_ interaction: TodoInteraction, _ optionID: String?, _ text: String?) -> Void
    let onSend: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            messageList
            Divider().opacity(0.5)
            ChatComposer(
                photoSelections: $photoSelections,
                canAddMoreAttachments: canAddMoreAttachments,
                maxNewAttachments: maxNewAttachments,
                isAgentRunning: isAgentRunning,
                onTakePhoto: onTakePhoto,
                onSend: onSend
            )
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(items) { item in
                        messageRow(for: item)
                            .id(item.id)
                            .transition(.opacity)
                    }
                    Color.clear
                        .frame(height: 8)
                        .id("__bottom")
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: items.count) { _, _ in
                withAnimation(.smooth(duration: 0.25)) {
                    proxy.scrollTo("__bottom", anchor: .bottom)
                }
            }
            .onAppear {
                proxy.scrollTo("__bottom", anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private func messageRow(for item: ConversationItem) -> some View {
        switch item {
        case .userRequest(let text, _):
            UserTextBubble(text: text)
        case .userAttachments(let ids):
            let attachments = ids.compactMap { attachmentsByID[$0] }
            UserAttachmentsBubble(
                attachments: attachments,
                urls: attachmentURLs,
                onRemove: onRemoveAttachment,
                onTap: onPreviewAttachment
            )
        case .userMessage(_, let text, _):
            UserTextBubble(text: text)
        case .agentStep(let step):
            AgentStepMessage(step: step, onOpenOAuth: onOpenOAuth)
        case .agentThinking(let label):
            AgentThinkingMessage(label: label)
        case .agentInteraction(let interaction):
            AgentInteractionMessage(
                interaction: interaction,
                submittingOptionID: submittingOptionID,
                onRespond: { optionID, text in
                    onRespondInteraction(interaction, optionID, text)
                }
            )
        case .agentError(let text):
            AgentErrorMessage(text: text)
        }
    }
}

// MARK: - User-side bubbles

private struct UserTextBubble: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 40)
            Text(text)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(Color.primary)
                .multilineTextAlignment(.leading)
                .padding(.vertical, 12)
                .padding(.horizontal, 18)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                )
                .textSelection(.enabled)
        }
    }
}

private struct UserAttachmentsBubble: View {
    let attachments: [TodoAttachment]
    let urls: [UUID: URL]
    let onRemove: (TodoAttachment) -> Void
    let onTap: (TodoAttachment) -> Void

    var body: some View {
        HStack {
            Spacer(minLength: 40)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(attachments) { attachment in
                        RemoteAttachmentTile(
                            signedURL: urls[attachment.id],
                            onRemove: { onRemove(attachment) },
                            onTap: { onTap(attachment) }
                        )
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxWidth: 280, alignment: .trailing)
        }
    }
}

// MARK: - Agent-side messages (no bubble background)

/// Single-line activity placeholder shown while the agent is actively
/// working but hasn't produced its final reply yet. The `label` is
/// derived in `ConversationBuilder` from the latest in-flight step so it
/// reflects what Hermes is doing right now — e.g. `Working on gmail send
/// email…` or `Reviewing web search result…`. Falls back to `Thinking…`.
///
/// Two animations layered on top of each other:
/// 1. `contentTransition(.opacity)` + an animation bound to `label`
///    crossfades smoothly when the line changes.
/// 2. A self-driven opacity pulse keeps the line subtly alive so the
///    user knows something is still happening between step updates.
///
/// The previous noisy stream of `thought` / `tool_started` / `tool_result`
/// rows is still inserted into `todo_steps` by the runner so other UIs
/// can read them — they just don't render in the chat thread anymore.
private struct AgentThinkingMessage: View {
    let label: String
    @State private var faded = false

    var body: some View {
        Text(label)
            .font(.system(size: 15, weight: .regular, design: .rounded))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .contentTransition(.opacity)
            .animation(.smooth(duration: 0.35), value: label)
            .opacity(faded ? 0.45 : 1.0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
                ) {
                    faded = true
                }
            }
            .accessibilityLabel("Hermes is \(label.lowercased())")
    }
}

private struct AgentStepMessage: View {
    let step: TodoStep
    let onOpenOAuth: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let toolName = step.tool_name, !toolName.isEmpty {
                Text(prettify(toolName))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            if let text = step.text, !text.isEmpty {
                Text(text)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if step.kind == .oauth_needed,
               let urlStr = step.url,
               let url = URL(string: urlStr) {
                Button {
                    onOpenOAuth(url)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Open authorization link")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(Color.orange)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.orange.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Text(step.ts.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func prettify(_ name: String) -> String {
        name
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "mcp ", with: "")
            .capitalized
    }
}

private struct AgentInteractionMessage: View {
    let interaction: TodoInteraction
    let submittingOptionID: String?
    let onRespond: (_ optionID: String?, _ text: String?) -> Void

    @State private var freeform: String = ""
    @FocusState private var freeformFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(interaction.prompt)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if let summary = interaction.summary, !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if let draft = interaction.emailDraft {
                EmailDraftPreview(draft: draft)
            } else if let content = interaction.content {
                JSONPreview(value: content)
            }

            if interaction.allowsFreeform {
                TextField(
                    interaction.freeformPlaceholder ?? "Add a note or instructions",
                    text: $freeform,
                    axis: .vertical
                )
                .lineLimit(1...6)
                .textFieldStyle(.roundedBorder)
                .focused($freeformFocused)
                .disabled(submittingOptionID != nil)
            }

            optionButtons
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var optionButtons: some View {
        let opts = interaction.options
        VStack(spacing: 8) {
            ForEach(opts) { opt in
                OptionButton(
                    option: opt,
                    isSubmitting: submittingOptionID == opt.id,
                    disabled: submittingOptionID != nil
                ) {
                    onRespond(opt.id, freeform)
                }
            }

            if opts.isEmpty && interaction.allowsFreeform {
                Button {
                    onRespond(nil, freeform)
                } label: {
                    HStack {
                        if submittingOptionID == "__freeform" {
                            ProgressView().controlSize(.small)
                        }
                        Text("Reply")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(submittingOptionID != nil
                          || freeform.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

private struct OptionButton: View {
    let option: InteractionOption
    let isSubmitting: Bool
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        let label = HStack {
            if isSubmitting {
                ProgressView().controlSize(.small)
            }
            Text(option.label)
                .frame(maxWidth: .infinity)
        }
        Group {
            switch option.style {
            case .destructive:
                Button(role: .destructive, action: action) { label }
                    .buttonStyle(.bordered)
            case .secondary:
                Button(action: action) { label }
                    .buttonStyle(.bordered)
            case .primary, .none:
                Button(action: action) { label }
                    .buttonStyle(.borderedProminent)
            }
        }
        .disabled(disabled)
    }
}

private struct EmailDraftPreview: View {
    let draft: (subject: String, body: String, to: [String])

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !draft.to.isEmpty {
                Text("To: \(draft.to.joined(separator: ", "))")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Text(draft.subject)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Text(draft.body)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(Color.primary)
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.10))
        )
    }
}

private struct JSONPreview: View {
    let value: JSONValue

    var body: some View {
        Text(prettyPrint(value))
            .font(.footnote.monospaced())
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            )
            .textSelection(.enabled)
    }

    private func prettyPrint(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value),
              let s = String(data: data, encoding: .utf8) else {
            return "(unparseable)"
        }
        return s
    }
}

private struct AgentErrorMessage: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .regular, design: .rounded))
            .foregroundStyle(.red)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Composer

/// Live chat composer. Text + send fire `onSend` with the trimmed draft;
/// the field and send button auto-disable while the agent is mid-turn so
/// the user can't pile messages on top of an in-flight Hermes run. The
/// paperclip menu remains available for attachments regardless of agent
/// state — uploads always work because they don't bother the agent.
private struct ChatComposer: View {
    @Binding var photoSelections: [PhotosPickerItem]
    let canAddMoreAttachments: Bool
    let maxNewAttachments: Int
    let isAgentRunning: Bool
    let onTakePhoto: () -> Void
    let onSend: (String) -> Void

    @State private var draft: String = ""
    @State private var showPhotosPicker = false
    @FocusState private var focused: Bool

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !isAgentRunning && !trimmedDraft.isEmpty
    }

    private var placeholder: String {
        isAgentRunning ? "Hermes is working…" : "Message Hermes"
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            attachMenu
                .disabled(!canAddMoreAttachments)
                .opacity(canAddMoreAttachments ? 1 : 0.4)

            TextField(placeholder, text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
                .focused($focused)
                .disabled(isAgentRunning)
                .submitLabel(.send)
                .onSubmit(submit)

            Button(action: submit) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .frame(width: 36, height: 36)
                    .background(
                        (canSend ? Color.accentColor : Color.primary.opacity(0.4)),
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .animation(.smooth(duration: 0.2), value: canSend)
        .animation(.smooth(duration: 0.2), value: isAgentRunning)
        .photosPicker(
            isPresented: $showPhotosPicker,
            selection: $photoSelections,
            maxSelectionCount: max(1, maxNewAttachments),
            matching: .images,
            photoLibrary: .shared()
        )
    }

    private func submit() {
        let text = trimmedDraft
        guard !text.isEmpty, !isAgentRunning else { return }
        onSend(text)
        draft = ""
        focused = false
    }

    private var attachMenu: some View {
        Menu {
            Button {
                onTakePhoto()
            } label: {
                Label("Take photo", systemImage: "camera.fill")
            }
            Button {
                showPhotosPicker = true
            } label: {
                Label("Choose from library", systemImage: "photo.on.rectangle")
            }
        } label: {
            Image(systemName: "paperclip")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.primary)
                .frame(width: 36, height: 36)
                .background(Color.primary.opacity(0.06), in: Circle())
        }
        .accessibilityLabel("Attach photo")
    }
}
