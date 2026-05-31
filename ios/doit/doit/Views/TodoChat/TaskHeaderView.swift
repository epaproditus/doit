import SwiftUI

/// Top panel of the split-screen detail view: a back chevron pinned to the
/// top-left (so navigation mirrors the system nav bar), a more-actions
/// (`ellipsis`) menu on the right that exposes "Stop task" while the agent
/// is still cancellable, and a compact status indicator + title + status
/// label below with extra breathing room from the action row.
struct TaskHeaderView: View {
    let todo: Todo
    /// User-visible deliverables produced by the agent (e.g. a created
    /// Google Sheet link, a sent email summary, a calendar invite). Each
    /// renders as a compact card under the title. Empty by default so
    /// older callers and previews don't need to plumb anything through.
    var artifacts: [TodoArtifact] = []
    let onBack: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.primary)
                            .frame(width: 36, height: 36)
                            .background(Color.primary.opacity(0.06), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")

                    Spacer(minLength: 8)

                    Text(todo.status.label)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .contentTransition(.opacity)
                        .animation(.smooth(duration: 0.3), value: todo.status)
                        .accessibilityLabel("Status: \(todo.status.label)")

                    Spacer(minLength: 8)

                    Menu {
                        Button("Delete Task", role: .destructive, action: onDelete)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 36)
                            .background(Color.primary.opacity(0.06), in: Circle())
                    }
                    // Suppress Menu's default accent (blue) tint so the
                    // ellipsis renders in the same neutral grey as the back
                    // chevron's symbol.
                    .buttonStyle(.plain)
                    .accessibilityLabel("More options")
                }

                // Metadata row: human-formatted creation time on the leading
                // side, connection logo on the trailing side. Mirrors the
                // top-row treatment on the home-feed task tile so the detail
                // view feels like a continuation of that card.
                HStack(alignment: .center, spacing: 8) {
                    Text(humanizedDate(todo.created_at))
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if let slug = todo.connection_slug, !slug.isEmpty {
                        ConnectionLogo(slug: slug)
                            .frame(width: 18, height: 18)
                            .accessibilityLabel("Connection: \(slug)")
                    }
                }
                .padding(.top, 12)

                HStack(alignment: .top, spacing: 12) {
                    StatusIndicatorIcon(status: todo.status)
                        .frame(width: 28, height: 28)

                    Text(todo.title)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)

                    Spacer(minLength: 0)
                }

                if !artifacts.isEmpty {
                    artifactsSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// One card per artifact stacked vertically. Lives just below the
    /// title so the deliverable sits next to the task it answers; the
    /// surrounding `ScrollView` lets the header expand when there are
    /// multiple artifacts without squeezing the chat panel.
    @ViewBuilder
    private var artifactsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(artifacts) { artifact in
                TaskArtifactView(artifact: artifact)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.smooth(duration: 0.25), value: artifacts.map(\.id))
        .padding(.top, 4)
    }

    /// Formats a creation timestamp the way iOS apps usually do — anchored
    /// to "Today" / "Yesterday" while the memory is still fresh, sliding
    /// into weekday names within the past week, then to month-day, and
    /// finally to month-day-year for older items. Always pairs the day
    /// part with a short time (`3:42 PM`).
    private func humanizedDate(_ date: Date) -> String {
        let cal = Calendar.current
        let now = Date()
        let timeStr = date.formatted(date: .omitted, time: .shortened)

        if cal.isDateInToday(date) {
            return "Today at \(timeStr)"
        }
        if cal.isDateInYesterday(date) {
            return "Yesterday at \(timeStr)"
        }
        if let days = cal.dateComponents([.day], from: date, to: now).day,
           days >= 0, days < 7 {
            let weekday = date.formatted(.dateTime.weekday(.wide))
            return "\(weekday) at \(timeStr)"
        }
        if cal.isDate(date, equalTo: now, toGranularity: .year) {
            let monthDay = date.formatted(.dateTime.month(.abbreviated).day())
            return "\(monthDay) at \(timeStr)"
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
            + " at \(timeStr)"
    }
}

/// Lightweight todo-checkbox style indicator: an unchecked circle for every
/// non-terminal state (subtly pulsing while the agent is actively working)
/// and a green filled checkmark once the task is done. Failure / auth /
/// input states intentionally stay as the unchecked circle — those are
/// already communicated by the status label below the title and the pill.
struct StatusIndicatorIcon: View {
    let status: TodoStatus

    var body: some View {
        Image(systemName: status == .done ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22, weight: .regular))
            .foregroundStyle(status == .done ? Color.green : Color.secondary)
            .symbolEffect(.pulse, isActive: status.isActive)
    }
}

// MARK: - Artifact card

/// Compact card the agent uses to surface a final deliverable — a created
/// doc/sheet link, a sent email, a calendar invite, or a text result.
/// Dispatches on `artifact.kind` to one of four small renderers; unknown
/// or empty payloads short-circuit to nothing so a malformed row never
/// leaves a blank tile in the header.
struct TaskArtifactView: View {
    let artifact: TodoArtifact

    var body: some View {
        Group {
            switch artifact.kind {
            case .link: LinkArtifactCard(artifact: artifact)
            case .email: EmailArtifactCard(artifact: artifact)
            case .calendar: CalendarArtifactCard(artifact: artifact)
            case .text: TextArtifactCard(artifact: artifact)
            }
        }
    }
}

/// Common visual shell every artifact card uses: rounded background, a
/// small leading icon, a title row, and a slot for kind-specific content.
/// Pulled out so the four renderers don't each re-implement the chrome.
private struct ArtifactCardShell<Content: View>: View {
    let icon: AnyView
    let title: String
    let trailing: AnyView?
    let onTap: (() -> Void)?
    @ViewBuilder var content: () -> Content

    init(
        icon: AnyView,
        title: String,
        trailing: AnyView? = nil,
        onTap: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.trailing = trailing
        self.onTap = onTap
        self.content = content
    }

    var body: some View {
        let card = VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                icon
                    .frame(width: 20, height: 20)
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                trailing
            }
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )

        if let onTap {
            Button(action: onTap) { card }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isLink)
        } else {
            card
        }
    }
}

/// Open-in-browser card for `link` artifacts. The leading glyph is the
/// provider's `ConnectionLogo` when we have a slug for it (gmail,
/// googlesheets, googledocs, …) and a generic link symbol otherwise.
private struct LinkArtifactCard: View {
    let artifact: TodoArtifact
    @Environment(\.openURL) private var openURL

    var body: some View {
        let title = artifact.title ?? artifact.url?.host ?? "Open link"
        let url = artifact.url
        let tap: (() -> Void)? = url.map { target in
            { openURL(target) }
        }
        ArtifactCardShell(
            icon: AnyView(providerIcon),
            title: title,
            trailing: AnyView(
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            ),
            onTap: tap
        ) {
            if let host = url?.host {
                Text(host)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    @ViewBuilder
    private var providerIcon: some View {
        if let slug = artifact.provider, !slug.isEmpty {
            ConnectionLogo(slug: slug)
        } else {
            Image(systemName: "link")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
        }
    }
}

/// Renders an email artifact as a "sent message" preview: To/Subject in
/// the header, body truncated below. Not tappable — the email already
/// lives in the user's outbox/Sent folder, so we just summarize.
private struct EmailArtifactCard: View {
    let artifact: TodoArtifact

    var body: some View {
        let draft = artifact.emailDraft
        let title = artifact.title ?? draft?.subject ?? "Email"
        ArtifactCardShell(
            icon: AnyView(
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)
            ),
            title: title
        ) {
            if let draft {
                VStack(alignment: .leading, spacing: 4) {
                    if !draft.to.isEmpty {
                        Text("To: \(draft.to.joined(separator: ", "))")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Text(draft.body)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
            }
        }
    }
}

/// Calendar invite preview: title + formatted date/time range,
/// attendees, location, and an "Add to Google Calendar" button when
/// the agent supplied a URL (typically a `calendar.google.com/event`
/// or `addeventatc` link).
private struct CalendarArtifactCard: View {
    let artifact: TodoArtifact
    @Environment(\.openURL) private var openURL

    var body: some View {
        let event = artifact.calendarEvent
        let title = event?.title ?? artifact.title ?? "Calendar event"
        ArtifactCardShell(
            icon: AnyView(
                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)
            ),
            title: title
        ) {
            VStack(alignment: .leading, spacing: 6) {
                if let when = event.flatMap({ Self.formatRange($0.start, $0.end) }) {
                    Label(when, systemImage: "clock")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                if let location = event?.location, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let attendees = event?.attendees, !attendees.isEmpty {
                    Label(attendees.joined(separator: ", "),
                          systemImage: "person.2.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if let url = event?.url {
                    Button {
                        openURL(url)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Open in Calendar")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(Color.blue)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
        }
    }

    /// Formats a start/end pair in the same style the rest of the detail
    /// view uses: short time on its own when both are missing, a single
    /// date+time when only `start` is known, and a compact range when
    /// both are present (collapsing the date side when start/end share
    /// the same day).
    private static func formatRange(_ start: Date?, _ end: Date?) -> String? {
        guard let start else { return nil }
        let startStr = start.formatted(date: .abbreviated, time: .shortened)
        guard let end else { return startStr }
        let cal = Calendar.current
        if cal.isDate(start, inSameDayAs: end) {
            let endTime = end.formatted(date: .omitted, time: .shortened)
            return "\(startStr) – \(endTime)"
        }
        let endStr = end.formatted(date: .abbreviated, time: .shortened)
        return "\(startStr) → \(endStr)"
    }
}

/// Plain-text deliverable (e.g. a generated summary or snippet). Kept
/// readable rather than scrollable; the text view selects so the user
/// can copy it out.
private struct TextArtifactCard: View {
    let artifact: TodoArtifact

    var body: some View {
        let body = artifact.text ?? ""
        ArtifactCardShell(
            icon: AnyView(
                Image(systemName: "text.alignleft")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)
            ),
            title: artifact.title ?? "Result"
        ) {
            if !body.isEmpty {
                Text(body)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }
}
