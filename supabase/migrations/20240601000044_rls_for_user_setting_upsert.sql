-- RLS policies allowing users to upsert their own model settings
-- and check their own premium model access.
--
-- Together with the function update (which now uses the user's JWT
-- for all DB operations), this removes the need for the Edge Function
-- to use a SUPABASE_SERVICE_ROLE_KEY secret.
--
-- Applied with: supabase db push --project-ref <ref>
-- Or via: Supabase Dashboard > SQL Editor

-- === agent_model_settings ===

-- Allow INSERT (the upsert path for new rows)
create policy "agent_model_settings_self_insert" on agent_model_settings
    for insert with check (auth.uid() = user_id);

-- Allow UPDATE (the upsert path for existing rows)
create policy "agent_model_settings_self_update" on agent_model_settings
    for update using (auth.uid() = user_id);

-- === premium_model_users ===

-- The table has `revoke all from public` + `grant to service_role`.
-- We need to re-grant SELECT at the table level so the authenticated
-- role can pass through to RLS, which then filters to their own row.
grant select on table premium_model_users to authenticated;

-- Allow users to check their own premium access
create policy "premium_model_users_self_select" on premium_model_users
    for select using (auth.uid() = user_id);
