# Deploy `agent-settings` Edge Function (PLY-309)

This document explains how to deploy the `agent-settings` Edge Function to
resolve the "Couldn't load model settings" 404 error (PLY-309).

## Root Cause

The `agent-settings` Edge Function was updated in PLY-305/PLY-308 to support
self-managed (BYO/self-host) model providers with a `base_url` field. This
function was:

- **Deployed on** `qjeutitqgdsasccxfxdy` (iOS dev) — but with **stale code**
  that lacks `base_url` support
- **Not deployed on** `nportxmsauhezjdubsma` (production) — returns HTTP 404

The iOS app calls this function when the user opens Model Settings. If the
function is not deployed (or has a stale version), the app shows:
> "Couldn't load model settings: Edge Function returned a non-2xx status code: 404"

## Prerequisites

- Supabase CLI installed (`npm install -g supabase` or `brew install supabase/tap/supabase`)
- A Supabase Personal Access Token (PAT) that has **Management API access**
  to the project's organization
  - Get one at: https://supabase.com/dashboard/account/tokens
  - Store it: `supabase login --token sbp_xxx`

## Deploy to Production (`nportxmsauhezjdubsma`)

```bash
# 1. Set required environment variables
export DOIT_SUPABASE_SERVICE_ROLE_KEY="eyJ...your_service_role_key"
export SUPABASE_ACCESS_TOKEN="sbp_xxx...your_pat"

# 2. Run the deploy script
./scripts/deploy-agent-settings.sh
```

The script will:
1. Link to the Supabase project
2. Set Edge Function secrets (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`)
3. Apply migration `20240601000043` (adds `base_url` column, changes `provider` to text)
4. Deploy the `agent-settings` function
5. Verify the function responds

## Deploy to Dev (`qjeutitqgdsasccxfxdy`)

```bash
export DOIT_SUPABASE_SERVICE_ROLE_KEY="eyJ..."
export SUPABASE_PROJECT_REF="qjeutitqgdsasccxfxdy"
./scripts/deploy-agent-settings.sh
```

## Deploy via GitHub Actions

The `.github/workflows/deploy-edge-functions.yml` workflow auto-deploys
on push to `main` that touches `supabase/functions/**` or
`supabase/migrations/**`. It requires the following repository secrets:

| Secret | Description |
| ------ | ----------- |
| `SUPABASE_ACCESS_TOKEN` | PAT with Management API access to the project's org |
| `SUPABASE_PROJECT_REF` | Project ref (e.g. `nportxmsauhezjdubsma`) |

To trigger manually:
1. Go to GitHub → Actions → "Deploy Edge Functions"
2. Click "Run workflow"
3. Enter the project ref and optionally specify `agent-settings` as the function

## Verify

After deployment, verify the function is live:

```bash
# Without auth — expect 401 (proves function exists)
curl -s -o /dev/null -w "%{http_code}" \
  -X POST "https://<project-ref>.supabase.co/functions/v1/agent-settings" \
  -H "Content-Type: application/json" \
  -d '{"action":"get"}'
# Expected: 401 (JWT verification active)

# With auth — expect 200 + catalog JSON
curl -s \
  -X POST "https://<project-ref>.supabase.co/functions/v1/agent-settings" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <valid-user-jwt>" \
  -d '{"action":"get"}'
# Expected: {"catalog": [...], "setting": ..., "default_selection": {...}}
```

Then test the save flow with a self-managed provider:

```bash
curl -s \
  -X POST "https://<project-ref>.supabase.co/functions/v1/agent-settings" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <valid-user-jwt>" \
  -d '{"action":"update","provider":"opencode-go","model":"deepseek-v4-flash","base_url":"http://localhost:8080"}'
# Expected: {"setting": {"provider": "opencode-go", "model": "deepseek-v4-flash", "base_url": "http://localhost:8080", ...}}
```

## Current Status

| Item | Dev (`qjeuti...`) | Prod (`nportxm...`) |
| ---- | ----------------- | ------------------- |
| Function deployed | ✅ Yes (stale code) | ❌ No (404) |
| Migration #43 applied | ❌ No | ❌ No |
| Latest code with base_url | ❌ No | ❌ No |
| Self-managed save works | ❌ No | ❌ No |

**Blocker**: The Supabase PAT (`sbp_e72fcaa3...`) does not have Management API
access to either project's organization. A new PAT with the correct org
permissions is needed.
