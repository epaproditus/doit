# PLY-309: Deploy agent-settings Edge Function

## Problem

The `agent-settings` Supabase Edge Function is not deployed on the **production** Supabase project (`nportxmsauhezjdubsma`), causing the iOS app to show a 404 error when it tries to load model settings.

The dev project (`qjeutitqgdsasccxfxdy`) has the function deployed and working with the latest code.

## Current State (as of July 17, 2026)

| Item | Dev (`qjeuti...`) | Prod (`nportxm...`) |
|------|--------------------|---------------------|
| Function deployed | Yes (working, returns 401 without auth) | No (returns HTTP 404) |
| Migration #43 (base_url, provider text) | Not checked | agent_model_settings table exists |
| Migration #44 (RLS policies) | Not applied | Not applied |
| Self-managed save works | Yes (function supports base_url) | No (function doesn't exist) |

## Root Cause

The Supabase PAT on this machine (`sbp_e72fca...`) is either expired or does not have Management API access to the production project's organization. All Management API calls return 401 Unauthorized.

The CI/CD workflow in `.github/workflows/deploy-edge-functions.yml` also needs a valid `SUPABASE_ACCESS_TOKEN` secret in GitHub.

## How to Deploy to Production

### Option A: Via Supabase Dashboard (Manual, no PAT needed)

1. Open the production project:
   https://supabase.com/dashboard/project/nportxmsauhezjdubsma

2. **SQL Editor** — Run migration #43:
   Open SQL Editor, paste and run the content of:
   supabase/migrations/20240601000043_self_hosted_provider_base_url.sql

3. **SQL Editor** — Run migration #44 (RLS policies):
   Open SQL Editor, paste and run the content of:
   supabase/migrations/20240601000044_rls_for_user_setting_upsert.sql

4. **Edge Functions** — Create "agent-settings":
   - Click "Create a new function"
   - Name: agent-settings
   - Paste the code from supabase/functions/agent-settings/index.ts
   - Click "Save and Deploy"
   - Under "Configuration", leave JWT verification enabled

5. **Settings > API** — Set 3 secrets for the Edge Function:
   - Go to Project Settings > API
   - Under "Project secrets", add:
     SUPABASE_URL=https://nportxmsauhezjdubsma.supabase.co
     SUPABASE_ANON_KEY=sb_publishable_Y_ug6gCljcKuPnst_s1TMw_oZ5BosqD
     SUPABASE_SERVICE_ROLE_KEY=<get from Service Role Key field>

### Option B: Via Supabase CLI (needs valid PAT)

```bash
cd ~/path/to/doit

SUPABASE_PROJECT_REF=nportxmsauhezjdubsma \
SUPABASE_DB_PASSWORD=<database_password> \
DOIT_SUPABASE_SERVICE_ROLE_KEY=<service_role_key> \
./scripts/pl-309-deploy.sh
```

The database password is at: Supabase Dashboard > Project Settings > Database.

### Option C: Via CI/CD (needs PAT set in GitHub secrets)

1. GitHub repo > Settings > Secrets and variables > Actions
2. Add secret SUPABASE_ACCESS_TOKEN with a valid PAT
3. Actions > "Deploy Edge Functions" > Run workflow
4. Check "apply_migrations" if migration #43 and #44 are not yet applied

## Verification

After deployment, verify the function is live:

```bash
# Should return 401 (function exists, auth required) — NOT 404
curl -s -o /dev/null -w "%{http_code}" -X POST \
  https://nportxmsauhezjdubsma.supabase.co/functions/v1/agent-settings \
  -H 'Content-Type: application/json' \
  -d '{"action":"get"}'
# Expected: 401
```

With a valid JWT, the function should return the full catalog:
```bash
TOKEN=$(curl -s -X POST \
  "https://nportxmsauhezjdubsma.supabase.co/auth/v1/signup" \
  -H "Content-Type: application/json" \
  -H "apikey: sb_publishable_Y_ug6gCljcKuPnst_s1TMw_oZ5BosqD" \
  -d '{}' | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))")

curl -s -X POST \
  "https://nportxmsauhezjdubsma.supabase.co/functions/v1/agent-settings" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"action":"get"}'
# Expected: {"catalog": [...], "setting": ..., "default_selection": {...}}
```

## iOS App Changes

Both SettingsView and ModelSettingsView have been updated to:
1. Skip the API call for self-managed mode — no 404 if the user is using BYO/self-host mode
2. Show a friendlier error message for 404s instead of the raw error
