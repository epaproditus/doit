# PLY-309: Deploy agent-settings Edge Function

## Problem

The `agent-settings` Edge Function is not deployed on the production Supabase project (`nportxmsauhezjdubsma`). The iOS app calls this function to load model settings, and the new ungated self-managed model feature exposes this code path. Without the function, users see:

> Couldn't load model settings: Edge Function returned a non-2xx status code: 404

## Current State

### Dev project (qjeutitqgdsasccxfxdy)
- Function IS deployed (returns catalog on GET with valid auth)
- But running **old code** — update with `base_url` returns `unsupported_provider`
- Migration `20240601000043` (base_url column + provider->text) NOT applied

### Production project (nportxmsauhezjdubsma)
- Function NOT deployed — returns 404
- This is where the iOS app hits the error
- This is the project targeted in `/etc/doit/connector.env`

### Code (on main, already pushed)
- `supabase/functions/agent-settings/index.ts` — correct PLY-308 logic (skips catalog validation when base_url is present)
- `supabase/migrations/20240601000043_self_hosted_provider_base_url.sql` — provider->text, adds base_url column
- `scripts/deploy-agent-settings.sh` — deploy script with per-project anon keys and DB password fallback
- `scripts/fix-agent-settings-deploy.sh` — one-shot fix script
- `scripts/deploy-edge-functions.sh` — generic deploy script
- `.github/workflows/deploy-edge-functions.yml` — CI/CD auto-deploy on push to supabase/ paths
- `ios/doit/Config/Local.xcconfig` — points to dev project (correct)

## Blocker

The Supabase PAT on this server (`sbp_e72f...`) does NOT have access to either project's Supabase organization. Management API returns 401 Unauthorized. Cannot deploy functions or apply migrations from this environment.

## How to Deploy

### Option A: Manual deploy from Mac (preferred)

```bash
# 1. Prerequisites
cd ~/path/to/doit
git pull origin main
npm install -g supabase      # if not installed
supabase login               # opens browser — generates new PAT

# 2. Deploy to DEV project (re-deploy with latest code)
SUPABASE_PROJECT_REF=qjeutitqgdsasccxfxdy \
DOIT_SUPABASE_SERVICE_ROLE_KEY=eyJ... \
./scripts/deploy-agent-settings.sh

# 3. Deploy to PRODUCTION project (fix the 404)
SUPABASE_PROJECT_REF=nportxmsauhezjdubsma \
DOIT_SUPABASE_SERVICE_ROLE_KEY=eyJ... \
./scripts/deploy-agent-settings.sh
```

The `DOIT_SUPABASE_SERVICE_ROLE_KEY` is found at:
Supabase Dashboard > Project Settings > API > service_role key

### Option B: GitHub Actions

Add these repo secrets, then trigger the workflow:
- `SUPABASE_ACCESS_TOKEN` — PAT with access to the project's org
- `SUPABASE_PROJECT_REF` — `nportxmsauhezjdubsma`

Go to: Actions > Deploy Edge Functions > Run workflow
Check "apply_migrations" = true

### Option C: Supabase Dashboard (manual)

1. Open https://supabase.com/dashboard/project/nportxmsauhezjdubsma
2. SQL Editor > Run the migration at `supabase/migrations/20240601000043_self_hosted_provider_base_url.sql`
3. Edge Functions > Create "agent-settings" with code from `supabase/functions/agent-settings/index.ts`
4. Set 3 secrets: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY

### Option D: From any machine with a valid PAT

```bash
SUPABASE_ACCESS_TOKEN=sbp_... \
SUPABASE_PROJECT_REF=nportxmsauhezjdubsma \
./scripts/deploy-edge-functions.sh agent-settings
```

## Verification

After deploy, the production endpoint should return 401 (function exists, needs auth) not 404:

```bash
curl -s -o /dev/null -w '%{http_code}' -X POST \
  https://nportxmsauhezjdubsma.supabase.co/functions/v1/agent-settings \
  -H 'Content-Type: application/json' \
  -d '{"action":"get"}'
# Expected: 401
```

With a valid JWT:
```bash
curl -s -X POST \
  https://nportxmsauhezjdubsma.supabase.co/functions/v1/agent-settings \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <valid_jwt>' \
  -d '{"action":"get"}'
# Expected: {"catalog": [...], "setting": ..., "default_selection": ...}

# Self-managed update with base_url should work:
curl -s -X POST \
  https://nportxmsauhezjdubsma.supabase.co/functions/v1/agent-settings \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <valid_jwt>' \
  -d '{"action":"update","provider":"opencode-go","model":"deepseek-v4-flash","base_url":"https://api.example.com"}'
# Expected: {"setting": {"provider": "opencode-go", ...}}
# NOT: {"error":"unsupported_provider"}
```

## Files Changed

- `supabase/functions/agent-settings/index.ts` — PLY-308 base_url bypass logic (already on main)
- `supabase/migrations/20240601000043_self_hosted_provider_base_url.sql` — schema update (already on main)
- `scripts/deploy-agent-settings.sh` — per-project anon keys + DB password fallback
- `scripts/fix-agent-settings-deploy.sh` — one-shot fix script (already on main)
- `scripts/deploy-edge-functions.sh` — generic deploy script (already on main)
- `.github/workflows/deploy-edge-functions.yml` — CI/CD workflow (already on main)
- `ios/doit/Config/Local.xcconfig` — iOS config (already on main)
- `DEPLOY-PLY-309.md` — this file
