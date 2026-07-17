# Deploy agent-settings Edge Function via Supabase Dashboard

This is the fastest way to deploy the `agent-settings` Edge Function to the
production Supabase project (`nportxmsauhezjdubsma`) — no CLI needed.

## Steps

### 1. Open the Supabase Dashboard

Go to: https://supabase.com/dashboard/project/nportxmsauhezjdubsma

### 2. Go to Edge Functions

In the left sidebar, click **Edge Functions**.

### 3. Create a new function

Click **Create a new function** button.

- **Name:** `agent-settings`
- **Slug:** `agent-settings` (auto-filled)
- **Source code:** Open the file at
  `supabase/functions/agent-settings/index.ts` and copy its entire contents
  (316 lines).
- **Verify JWT:** Leave it ON (the function handles its own auth)

Paste the code into the editor and click **Deploy**.

### 4. Verify the function is live

```bash
curl -s -o /dev/null -w "HTTP %{http_code}" -X POST \
  "https://nportxmsauhezjdubsma.supabase.co/functions/v1/agent-settings" \
  -H "Content-Type: application/json" \
  -d '{"action":"get"}'
```

Expected output: `HTTP 401` (unauthorized, which means the function is live
and checking auth). Before deploy, this returned 404.

### 5. Test with a valid user token (optional)

To confirm the function returns data:

```bash
# Sign up an anonymous user to get a token
TOKEN=$(curl -s -X POST \
  "https://nportxmsauhezjdubsma.supabase.co/auth/v1/signup" \
  -H "apikey: sb_publishable_Y_ug6gCljcKuPnst_s1TMw_oZ5BosqD" \
  -H "Content-Type: application/json" \
  -d '{}' | python3 -c "import json,sys; print(json.load(sys.stdin).get('access_token',''))")

# Call the function with the token
curl -s -X POST \
  "https://nportxmsauhezjdubsma.supabase.co/functions/v1/agent-settings" \
  -H "apikey: sb_publishable_Y_ug6gCljcKuPnst_s1TMw_oZ5BosqD" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"action":"get"}' | python3 -m json.tool
```

Expected: 200 with `{ catalog: [...], setting: null, default_selection: {...} }`

### 6. Rebuild iOS app

Rebuild the iOS app from Xcode (or distribute a new TestFlight build).
The model settings screen should no longer show the 404 error.

## If you prefer CLI

From a machine with a valid Supabase PAT:

```bash
supabase login
cd <repo-root>
supabase functions deploy agent-settings \
  --project-ref nportxmsauhezjdubsma \
  --no-verify-jwt \
  --use-api
```

The PAT `sbp_e72f...` on this Linux VM is invalid (returns 401 on all
Management API calls). You'll need a valid PAT from your Supabase account
at https://supabase.com/dashboard/account/tokens.

## Background

- The `agent-settings` Edge Function was updated (PLY-308/PLY-309) to support
  self-managed (BYO) model configuration with `base_url` support.
- It no longer requires `SUPABASE_SERVICE_ROLE_KEY` — all DB operations use
  the authenticated user's JWT with RLS policies.
- The function is already deployed on the dev project `qjeutitqgdsasccxfxdy`
  and works correctly there.
- The production connector service at `nportxmsauhezjdubsma` uses the same
  function but it was never deployed there, causing the 404.
- iOS code on `main` already has guards to skip API calls for self-managed
  mode, but hosted-mode users also need this function deployed.
