-- APNs environment-aware device tokens and ActivityKit Live Activity tokens.
--
-- Normal notification tokens are environment-specific (sandbox for Xcode
-- installs, production for TestFlight/App Store). ActivityKit push tokens are
-- also bound to an APNs environment and expire with the system Live Activity.

-- Existing rows predate environment tracking. Production is the safer default
-- for TestFlight/App Store, and newly-updated clients will overwrite their
-- current token with the precise environment on next launch.
alter table devices
    add column if not exists apns_environment text not null default 'production'
    check (apns_environment in ('sandbox', 'production'));

create index if not exists devices_user_environment_idx
    on devices (user_id, apns_environment, updated_at desc);

create table if not exists todo_live_activity_tokens (
    id               uuid primary key default gen_random_uuid(),
    todo_id          uuid not null references todos(id) on delete cascade,
    user_id          uuid not null references auth.users(id) on delete cascade,
    activity_id      text not null,
    push_token       text not null,
    apns_environment text not null check (apns_environment in ('sandbox', 'production')),
    created_at       timestamptz not null default now(),
    updated_at       timestamptz not null default now(),
    ended_at         timestamptz,
    unique (todo_id, activity_id),
    unique (push_token)
);

create index if not exists todo_live_activity_tokens_active_idx
    on todo_live_activity_tokens (todo_id, apns_environment, updated_at desc)
    where ended_at is null;

create trigger todo_live_activity_tokens_set_updated_at
    before update on todo_live_activity_tokens
    for each row execute function set_updated_at();

alter table todo_live_activity_tokens enable row level security;

create policy "todo_live_activity_tokens_self_select" on todo_live_activity_tokens
    for select using (auth.uid() = user_id);

create policy "todo_live_activity_tokens_self_insert" on todo_live_activity_tokens
    for insert with check (auth.uid() = user_id);

create policy "todo_live_activity_tokens_self_update" on todo_live_activity_tokens
    for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "todo_live_activity_tokens_self_delete" on todo_live_activity_tokens
    for delete using (auth.uid() = user_id);
