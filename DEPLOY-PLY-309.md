# PLY-309: Deploy agent-settings Edge Function

## Problem

The `agent-settings` Supabase Edge Function is not deployed on the production
project (`nportxmsauhezjdubsma`). The iOS app calls this function to load
model settings, and the new ungated self-managed model feature (PLY-308)
exposes this code path. Without the function, users see:

> Couldn't load model settings: Edge Function returned a non-2xx status code: 404

## Current State

| Project | Ref | agent-settings | Migration #43 |
|---------|-----|---------------|---------------|
| iOS Dev | `qjeutitqgdsasccxfxdy` | Deployed (old code — missing base_url support) | Not applied |
| Production | `nportxmsauhezjdubsma` | **Not deployed — returns 404** | Not applied |

## How to Deploy

### Prerequisites (one-time)

```bash
npm install -g supabase
supabase login                  # opens browser for PAT
git checkout main && git pull   # latest code
```

Get the service role keys from **Supabase Dashboard > Project Settings > API**:

| Project | Dashboard URL |
|---------|--------------|
| Dev | https://supabase.com/dashboard/project/qjeutitqgdsasccxfxdy |
| Production | https://supabase.com/dashboard/project/nportxmsauhezjdubsma |

### Deploy (from Mac)

```bash
cd ~/path/to/doit

# Set service role keys (get from dashboard)
export DOIT_DEV_SERVICE_ROLE_KEY=eyJ...    # dev project key
export DOIT_PROD_SERVICE_ROLE_KEY=eyJ...   # production project key

# Deploy to BOTH projects + apply migrations
./scripts/deploy-all-projects.sh
```

### Deploy individually (if script doesn't work)

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

### Via GitHub Actions

Set these repo secrets then trigger the workflow:
- `SUPABASE_ACCESS_TOKEN` — PAT with Management API access to both projects
- `SUPABASE_PROJECT_REF` — default project ref

Go to: **Actions > Deploy Edge Functions > Run workflow** (check "apply_migrations")

### Manual (Supabase Dashboard)

1. Open `https://supabase.com/dashboard/project/nportxmsauhezjdubsma`
2. **SQL Editor** → Run the migration at `supabase/migrations/20240601000043_self_hosted_provider_base_url.sql`
3. **Edge Functions** → Create "agent-settings" with code from `supabase/functions/agent-settings/index.ts`
4. **Settings** → Set 3 secrets: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`
5. Repeat for project `qjeutitqgdsasccxfxdy`

## Verification

After deploy, both projects should return HTTP 401 (not 404):

```bash
# Should return 401 (function exists, auth required)
curl -s -o /dev/null -w '%{http_code}' -X POST \
  https://nportxmsauhezjdubsma.supabase.co/functions/v1/agent-settings \
  -H 'Content-Type: application/json' \
  -d '{"action":"get"}'
# Expected: 401
```

With a valid JWT (from the iOS app):
```bash
curl -s -X POST \
  https://nportxmsauhezjdubsma.supabase.co/functions/v1/agent-settings \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <valid_jwt>' \
  -d '{"action":"get"}'
# Expected: {"catalog": [...], "setting": ..., "default_selection": {...}}
```

### Self-managed save test
```bash
# Should succeed (no catalog validation when base_url provided)
curl -s -X POST \
  https://nportxmsauhezjdubsma.supabase.co/functions/v1/agent-settings \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <valid_jwt>' \
  -d '{"action":"update","provider":"opencode-go","model":"deepseek-v4-flash","base_url":"https://api.example.com"}'
# Expected: {"setting": {"provider": "opencode-go", ...}}
# NOT: {"error":"unsupported_provider"}
```
