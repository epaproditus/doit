# PLY-309: Deploy agent-settings Edge Function

## Problem

The `agent-settings` Supabase Edge Function has not been deployed with the latest code (PLY-308 self-managed model support) on either Supabase project:

- **Dev** (`qjeutitqgdsasccxfxdy`): Function is deployed but with **stale code** (missing `base_url` support for self-managed providers)
- **Production** (`nportxmsauhezjdubsma`): Function is **not deployed at all** (returns HTTP 404)

The iOS app calls this function when the user opens Model Settings. Without the updated function, users see:
> Couldn't load model settings: Edge Function returned a non-2xx status code: 404

The root cause is that the Supabase PAT on this server does not have Management API access to either project's organization.

## Current State

| Item | Dev (`qjeuti...`) | Prod (`nportxm...`) |
| ---- | ----------------- | ------------------- |
| Function deployed | Yes (stale code) | No (404) |
| Migration #43 (base_url column) | Not applied | Not applied |
| Self-managed save works | No | No |

## Prerequisites (from Mac)

```bash
npm install -g supabase
supabase login                  # opens browser for PAT
git checkout main && git pull   # latest code
```

Get the service role keys from **Supabase Dashboard > Project Settings > API**:

| Project | Dashboard URL |
|---------|--------------|
| Dev | https://supabase.com/dashboard/project/qjeutitqgdsasccxfxdy/settings/api |
| Production | https://supabase.com/dashboard/project/nportxmsauhezjdubsma/settings/api |

## How to Deploy

### Option A: Deploy Script (recommended)

```bash
cd ~/path/to/doit

# Set service role keys (from dashboard)
export DOIT_DEV_SERVICE_ROLE_KEY=eyJ...    # dev project key
export DOIT_PROD_SERVICE_ROLE_KEY=eyJ...   # production project key

# Deploy to BOTH projects + apply migrations
./scripts/deploy-all-projects.sh
```

### Option B: Deploy individually

```bash
# Deploy to DEV (re-deploy with latest code + migration)
SUPABASE_PROJECT_REF=qjeutitqgdsasccxfxdy \
DOIT_SUPABASE_SERVICE_ROLE_KEY=eyJ... \
./scripts/deploy-agent-settings.sh

# Deploy to PRODUCTION (fix the 404 + migration)
SUPABASE_PROJECT_REF=nportxmsauhezjdubsma \
DOIT_SUPABASE_SERVICE_ROLE_KEY=eyJ... \
./scripts/deploy-agent-settings.sh
```

### Option C: Manual (Supabase Dashboard)

1. Open the project dashboard (URLs above)
2. **SQL Editor** → Run the migration at `supabase/migrations/20240601000043_self_hosted_provider_base_url.sql`
3. **Edge Functions** → Create/update "agent-settings" with code from `supabase/functions/agent-settings/index.ts`
4. **Settings > API** → Set 3 secrets: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`

## Verification

After deploy, both projects should return HTTP 401 (not 404):

```bash
# Should return 401 (function exists, auth required)
curl -s -o /dev/null -w "%{http_code}" -X POST \
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
# Expected: {"catalog": [...], "setting": ..., "default_selection": {...}}
```

Self-managed save test:
```bash
curl -s -X POST \
  https://nportxmsauhezjdubsma.supabase.co/functions/v1/agent-settings \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <valid_jwt>' \
  -d '{"action":"update","provider":"opencode-go","model":"deepseek-v4-flash","base_url":"https://api.example.com"}'
# Expected: {"setting": {"provider": "opencode-go", ...}}
# NOT: {"error":"unsupported_provider"}
```
