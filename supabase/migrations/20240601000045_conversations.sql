-- Conversations for the new Hybrid Chat Mode.
--
-- Unlike todos (one-shot tasks with a lifecycle), conversations represent an
-- ongoing back-and-forth between the user and the agent. Each conversation
-- maintains its own Hermes session so the agent's memory persists across
-- turns without a todo-style lifecycle (preparing → requested → running →
-- done).
--
-- The runner creates a conversation on first message and reuses the same
-- session for follow-ups. There is no "completion" — the user simply stops
-- replying, or explicitly archives the conversation.

create table conversations (
    id                uuid primary key default gen_random_uuid(),
    user_id           uuid not null references auth.users(id) on delete cascade,
    title             text not null default 'New conversation',
    -- Sticky state for the chat session. Most conversations stay 'active';
    -- the runner flips to 'archived' on explicit user request or after a
    -- long idle period.
    status            text not null default 'active'
                          check (status in ('active', 'archived')),
    hermes_session_id text,  -- stable Hermes session id for this conversation
    hermes_run_id     text,  -- current/last Hermes run id
    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),
    archived_at       timestamptz
);

create index conversations_user_id_idx
    on conversations (user_id, updated_at desc);

create index conversations_user_active_idx
    on conversations (user_id) where status = 'active';

-- One chat message within a conversation. Replaces the role-specific split
-- (todo_messages = user only, todo_steps = agent only) with a unified
-- message log where the runner writes both sides so the iOS app has a
-- single ordered stream per conversation.
--
-- The runner sets `role = 'assistant'` for agent replies and `role = 'user'`
-- for user messages. The iOS app inserts user messages and subscribes to
-- realtime for both.
create table conversation_messages (
    id              uuid primary key default gen_random_uuid(),
    conversation_id uuid not null references conversations(id) on delete cascade,
    user_id         uuid not null references auth.users(id) on delete cascade,
    role            text not null default 'user'
                        check (role in ('user', 'assistant')),
    body            text not null check (char_length(body) between 1 and 10000),
    -- Structured payload for non-text content: image references, audio
    -- attachments, artifact mentions, etc.
    payload         jsonb,
    created_at      timestamptz not null default now()
);

create index conversation_messages_conversation_id_idx
    on conversation_messages (conversation_id, created_at);

-- =========================================================================
-- Row-Level Security
-- =========================================================================

alter table conversations       enable row level security;
alter table conversation_messages enable row level security;

-- conversations: users CRUD their own
create policy "conversations_self_select" on conversations
    for select using (auth.uid() = user_id);

create policy "conversations_self_insert" on conversations
    for insert with check (auth.uid() = user_id);

create policy "conversations_self_update" on conversations
    for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "conversations_self_delete" on conversations
    for delete using (auth.uid() = user_id);

-- conversation_messages: users read/insert their own; runner writes assistant
-- messages via service_role (bypasses RLS).
create policy "conversation_messages_self_select" on conversation_messages
    for select using (auth.uid() = user_id);

create policy "conversation_messages_self_insert" on conversation_messages
    for insert with check (auth.uid() = user_id);

-- =========================================================================
-- Realtime
-- =========================================================================

alter publication supabase_realtime add table conversations;
alter publication supabase_realtime add table conversation_messages;

-- =========================================================================
-- Auto-update updated_at
-- =========================================================================

create trigger conversations_set_updated_at
    before update on conversations
    for each row execute function set_updated_at();
