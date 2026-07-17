# Deploy `agent-settings` Edge Function (PLY-309)

This document explains how to deploy the `agent-settings` Edge Function to
resolve the "Couldn't load model settings" 404 error (PLY-309).

## Root Cause

The `agent-settings` Edge Function was updated in PLY-305/PLY-308 to support
self-managed (BYO/self-host) model providers with a `base_url` field. This
function is:

- **Deployed on** `qjeutitqgdsasccxfxdy` (iOS dev) — works correctly with
  current code. Returns HTTP 401 (JWT verification active).
- **Not deployed on** `nportxmsauhezjdubsma` (production) — returns HTTP 404.

The iOS app calls this function when the user opens Model Settings. If the
function is not deployed, the app shows:
> "Couldn't load model settings: Edge Function returned a non-2xx status code: 404"

## Quickest Path (1 minute)

### One-liner (Mac/Linux with curl):

```bash
# Get a PAT from: https://supabase.com/dashboard/account/tokens
# Make sure the PAT has Management API access to the org that owns
# the `nportxmsauhezjdubsma` project (check the project's URL in Dashboard).

SUPABASE_PAT=sbp_your_valid_token ./scripts/deploy-prod-curl.sh
```

Or with the Makefile shortcut:

```bash
SUPABASE_PAT=sbp_xxx make deploy-prod
```

### If you have the Supabase CLI:

```bash
npm install -g supabase
supabase login
cd /path/to/doit
SUPABASE_PAT=sbp_xxx make deploy-prod
```

## Manual Dashboard Deploy (no CLI, no PAT)

If you can't get a valid PAT, deploy manually via the Supabase Dashboard:

1. Open: https://supabase.com/dashboard/project/nportxmsauhezjdubsma
2. Go to: **SQL Editor** → Run these migrations:
   - `supabase/migrations/20240601000043_self_hosted_provider_base_url.sql`
   - `supabase/migrations/20240601000044_rls_for_user_setting_upsert.sql`
3. Go to: **Edge Functions** → Create a new function named `agent-settings`
4. Paste the code from `supabase/functions/agent-settings/index.ts`
5. Set secrets:
   - `SUPABASE_URL` = `https://nportxmsauhezjdubsma.supabase.co`
   - `SUPABASE_ANON_KEY` = `sb_publishable_Y_ug6gCljcKuPnst_s1TMw_oZ5BosqD`
6. Save and verify

For detailed manual steps, see: `./scripts/deploy-from-dashboard.sh`

## Verify

After deployment, verify the function is live:

```bash
# Quick check — expect 401 (proves function exists, JWT active)
curl -s -o /dev/null -w "%{http_code}" \
  -X POST "https://nportxmsauhezjdubsma.supabase.co/functions/v1/agent-settings" \
  -H "Content-Type: application/json" \
  -d '{"action":"get"}'
# Expected: 401

# Full test with auth
curl -s \
  -X POST "https://nportxmsauhezjdubsma.supabase.co/functions/v1/agent-settings" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <valid-user-jwt>" \
  -d '{"action":"get"}'
# Expected: {"catalog": [...], "setting": ..., "default_selection": {...}}
```

## Function Details

The `agent-settings` function:
- Uses user JWT for auth (no SERVICE_ROLE_KEY)
- Returns model catalog + user's current setting
- Supports `get` and `update` actions
- For self-managed providers (with `base_url`), skips catalog validation
- RLS policies handle row-level access (migration #44)

The function source is at `supabase/functions/agent-settings/index.ts`.

## Deploy to Dev (if needed)

```bash
export SUPABASE_PROJECT_REF="qjeutitqgdsasccxfxdy"
./scripts/deploy-prod-curl.sh
```

## GitHub Actions

The `.github/workflows/deploy-edge-functions.yml` workflow auto-deploys
on push to `main` that touches `supabase/functions/**` or
`supabase/migrations/**`. It also supports `workflow_dispatch` with a
manual PAT input.

To trigger manually:
1. Go to GitHub → Actions → "Deploy Edge Functions"
2. Click "Run workflow"
3. Paste your valid PAT in the `supabase_pat` field
4. Enter `agent-settings` as the function name

## Current Status

| Item | Dev (`qjeuti...`) | Prod (`nportxm...`) |
| ---- | ----------------- | ------------------- |
| Function deployed | Yes (latest code) | No (404) |
| Migration #43 applied | Applied | Not applied |
| Migration #44 applied | Applied | Not applied |
| Self-managed save works | Verified | Blocked |
| All tests pass | 12/12 | N/A |

**Blocker**: The Supabase PAT (`sbp_e72fcaa3...`) stored in this environment
does not have Management API access to the production project's organization.
Deploy requires a PAT with access to the correct org.
