# Chatbot Tab — Investigation (PLY-259)

**Status:** Complete  
**Date:** 2026-07-16  
**Issue:** [PLY-259](https://linear.app/epaphroditus/issue/PLY-259/investigate-adding-a-chatbot-fourth-tab-similar-to-tasks)

## Summary

The app should support a fourth tab for a chatbot experience. The tab is architecturally feasible with ~90% reuse of existing chat UI. The heavy lift is backend (new schema, runner processing path, store), not iOS.

## Existing Tab Architecture

The app has 3 horizontal-paging sections defined by `TodoListSection` enum (`TodoListView.swift:3344`), not a standard SwiftUI `TabView`:

| Section | Index | Content |
|---|---|---|
| `.todo` (Tasks) | 0 | Active todos list + FAB |
| `.scheduled` (Scheduled) | 1 | Cron job grid |
| `.done` (Passbook) | 2 | Completed tasks + memories + location actions |

Tabs are rendered as a horizontal `LazyHStack` with `.scrollTargetBehavior(.paging)`. The bottom dock (`dockControls`, line 777) iterates `TodoListSection.allCases` to render buttons. The title header uses `SlidingSectionTitle` (line 3670) which animates a horizontally offset title per section. Badge counts come from `waitingBadgeCount` (line 846).

Adding a `.chat` case to `TodoListSection` automatically creates a dock button in the `ForEach(TodoListSection.allCases)` loop at line 777 — no separate tab bar configuration needed.

## Existing Chat Infrastructure (Reusable)

The app already has two chat contexts sharing the same renderer:

| Component | File | Usage |
|---|---|---|
| `TodoChatThread` | `TodoChatThread.swift` | ScrollView of ConversationItems + ChatComposer. Used by TodoDetailView and CronJobDetailView |
| `ChatComposer` | `TodoChatThread.swift:1026` | Text drafting, voice recording, photo picker, @ artifact mentions, reply hints |
| `ConversationItem` | `ConversationItem.swift` | `.userRequest`, `.userMessage`, `.agentStep`, `.agentThinking`, `.agentInteraction`, `.agentError`, `.agentReadyToRun`, `.agentArtifact` |
| `ConversationBuilder` | `ConversationItem.swift:57` | Builds `[ConversationItem]` from source rows |
| `CronConversationBuilder` | `CronConversationBuilder.swift` | Same pattern for cron jobs |

All seven `ConversationItem` message types apply to a standalone chatbot. The `TodoChatThread` component has no hard task dependency at the rendering layer — it accepts `[ConversationItem]` and an `onSend` callback.

## How Closely It Can Mirror the Tasks Tab

| Feature | Tasks Tab | Chatbot Tab |
|---|---|---|
| Scrollable content | `LazyVStack` of todo cards | `ScrollView` of `ConversationItem`s |
| Pull-to-refresh | `.refreshable` | Same |
| Scroll-to-bottom | Default scroll anchor bottom | Already default in `TodoChatThread` |
| Empty state | `EmptyState(section:)` | New empty state ("Start a conversation...") |
| Composer | FAB -> `AddTodoMorphOverlay` | `ChatComposer` (embedded in the tab, not FAB) |
| Navigation push | `TodoListDestination` | Not needed (detail is inline) |
| Section header | `SlidingSectionTitle` | Same mechanism, auto-expands |
| Badge count | `waitingBadgeCount` | Same pattern, shows unread replies |

### Where the Tasks Pattern Breaks

1. **No status concept.** A chatbot conversation has no "done" state. The tab shows a continuous transcript, not a list of items with lifecycle states.
2. **No "Do it" confirmation.** The `agentReadyToRun` bubble and `onConfirmRun` callback are task-specific. The chatbot skips these entirely.
3. **No artifacts header.** Task detail views show an artifacts section. Chatbot messages carry artifacts inline (already supported by `ConversationItem.agentArtifact`).
4. **Composer is embedded, not modal.** Tasks use a floating action button (`FAB`) that morphs into `AddTodoMorphOverlay`. The chatbot embeds `ChatComposer` at the bottom of the transcript, similar to the existing per-todo chat detail view.

## UI Changes Required

### iOS — Minimal surface area (~50 lines of Swift)

1. **TodoListSection enum** (`TodoListView.swift:3344`): Add `.chat` case with:
   - `index = 3`
   - `title = "Chat"`
   - `symbolName = "message.fill"`
   - `allowsAddTodoComposer = false`

2. **sectionPage(_:)**: Add a `case .chat` in the `LazyHStack` that renders `ChatView` (a thin wrapper around `TodoChatThread` with a `ChatStore` datasource).

3. **SlidingSectionTitle** (line 3670): No changes needed — iterates `TodoListSection.allCases` titles automatically.

4. **dockControls** (line 777): No changes needed — `ForEach(TodoListSection.allCases)` auto-picks up the new section.

5. **waitingBadgeCount** (line 846): Add `.chat` case returning 0 (or unread count from `ChatStore`).

6. **TopControls sliding section title**: Add "Chat" to the title set — auto-derived from the enum.

### iOS — New components

1. **ChatStore**: New `@Observable` store following the same pattern as `TodoStore`, with Supabase Realtime subscription through `TodoRealtimeHub`. Manages a single active conversation's messages.
2. **ChatView**: Wrapper view that creates `TodoChatThread` with `ChatStore` as datasource and wires `onSend` to create a new conversation message.
3. **ChatConversationBuilder**: New builder following `ConversationBuilder`/`CronConversationBuilder` pattern to produce `[ConversationItem]` from `conversation_messages` rows.

## Technical Constraints

### 1. Schema — No standalone conversation table exists

Every message today FK's to a parent:
- `todo_messages` -> `todos(id)`
- `cron_job_messages` -> `cron_jobs(id)`

A chatbot tab needs new tables:

```
conversations
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid()
  user_id     uuid REFERENCES auth.users(id)
  title       text
  created_at  timestamptz DEFAULT now()
  updated_at  timestamptz DEFAULT now()

conversation_messages
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid()
  conversation_id uuid REFERENCES conversations(id) ON DELETE CASCADE
  user_id         uuid REFERENCES auth.users(id)
  role            text CHECK (role IN ('user', 'assistant'))
  body            text
  artifact_json   jsonb
  consumed_at     timestamptz
  created_at      timestamptz DEFAULT now()
```

Plus `conversation_interactions` if the option-button pattern is needed. RLS and Realtime publication follow the existing patterns.

**Migration cost:** One migration file, same pattern as `20240601000010_todo_messages.sql` and `20240601000012_cron_job_chat.sql`.

### 2. Runner — No standalone chat processing path

The runner (`runner.py`) and BYO connector (`connector.py`) select work by polling:
- `todos WHERE status IN ('requested', 'preparing')`
- `cron_jobs WHERE state = 'scheduled'`

There is no poller for unconsumed conversation messages. Adding one requires a new worker loop:

```
poll conversation_messages WHERE consumed_at IS NULL
  -> claim (UPDATE consumed_at = now())
  -> build prompt (no task framing)
  -> HermesClient.start_run()
  -> stream_events() -> write back to conversation_messages
```

This mirrors the existing cron job worker loop structure.

### 3. System prompt — Fundamentally different framing

Current `SYSTEM_INSTRUCTIONS` (`hermes.py:39`) starts with:

> "You are a personal assistant completing one todo at a time."

A standalone chat needs an open-ended general assistant persona:
- No prep pass (`preparing` -> `requested` -> `running` lifecycle)
- No "Do it" confirmation bubble
- No artifact lifecycle management
- Continuous conversation (stable session across messages)

The existing `session_id` parameter already supports this — use a stable value like `doit-chat-{user_id}` instead of per-todo `doit-todo-{todo_id}`.

### 4. Store — New ChatStore needed

`TodoStore` manages todos, cron jobs, interactions, and artifacts. Conversations need their own `@Observable` store following the same pattern, with:
- Supabase Realtime subscription through `TodoRealtimeHub`
- `conversation_messages` fetch on appear
- Message insert handling
- Unread count tracking

### 5. Push notifications

Chat replies need push. Currently push fires on `todos` status changes. A new Realtime subscription on `conversation_messages` or a `notify_chat_message` Edge Function would be needed. This is blocked on a paid Apple Developer account for APNs capability.

## Implementation Paths

### Path A — Lightest: Reuse todos for chat (1-2 days)

A "Chat with Hermes" button that creates a todo with the user's message and opens the detail view. Existing `todo_messages` + runner flow handles everything:
- User types a message -> app creates a todo with `status=requested` -> runner picks it up -> conversation proceeds in task detail view
- Zero schema changes, zero runner changes
- Downside: pollutes the task list, uses task-oriented system prompt

### Path B — Full standalone chat (1-2 weeks) [RECOMMENDED]

New Supabase tables + runner poll loop + new iOS store + 4th tab:
- `conversations` and `conversation_messages` tables
- `ChatStore` with Realtime subscription
- `ChatView` using `TodoChatThread` component
- Standalone Hermes session with chat-appropriate system prompt
- New `claim_next_chat()` / `insert_chat_step()` connector API functions
- Chat push notifications

### Path C — Direct Hermes streaming from app (1-2 weeks)

Skip the runner for chat entirely. iOS app calls `POST /v1/runs` directly on Hermes and reads SSE stream:
- Fastest response (no poll latency)
- Works without the connector running
- Architecture boundary violation — app needs Hermes URL + API key
- Must still sync to Supabase for persistence

**Recommendation: Path B** — matches the existing architecture pattern (cron jobs are already a parallel work type), gives the cleanest UX, doesn't violate the app-connector boundary. Path A is a valid first step to validate demand before investing in the full schema + runner + store stack.

## Closest Existing Parallel

The cron job chat (`CronJobDetailView` + `CronConversationBuilder` + `cron_job_messages` table) already proves the pattern of chat-without-full-todo-lifecycle. A standalone chatbot tab follows the same architecture without the scheduling layer.
