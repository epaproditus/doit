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
| iOS Dev | `qjeutitqgdsasccxfxdy` | Deployed (needs redeploy for latest code) | Not applied |
| Production | `nportxmsauhezjdubsma` | **Not deployed — returns 404** | Not applied |

## Root Cause

Two separate issues:

1. **Production project**: The function was never deployed. Returning HTTP 404.
2. **Both projects**: Migration `20240601000043` (provider column to text,
   add base_url column) was never applied, so self-managed model saves fail.

## GitHub Actions Auto-Deploy

The workflow at `.github/workflows/deploy-edge-functions.yml` deploys to BOTH
projects automatically whenever `supabase/functions/**` or `supabase/migrations/**`
changes on main. It requires:

1. `SUPABASE_ACCESS_TOKEN` secret — a Supabase PAT with Management API access
   to BOTH projects' organizations. Get one at:
   https://supabase.com/dashboard/account/tokens
   (must be created in the same organization that owns the project)

If the PAT only has access to one organization, the prod deployment step will
gracefully fail and print instructions for manual deploy.

## Manual Deploy (one-shot)

### Option A: Deploy via Supabase CLI

```bash
npm install -g supabase
supabase login                    # opens browser for PAT
cd ~/path/to/doit && git pull origin main

# Deploy to production project
supabase link --project-ref nportxmsauhezjdubsma
supabase functions deploy agent-settings --project-ref nportxmsauhezjdubsma

# Apply the migration
supabase db push --project-ref nportxmsauhezjdubsma
```

### Option B: Deploy via Management API (direct script)

```bash
export SUPABASE_PAT="sbp_xxx..."  # PAT with Management API access
export DOIT_SUPABASE_SERVICE_ROLE_KEY="eyJ..."  # from Dashboard > Settings > API
./scripts/deploy-agent-settings-direct.sh
```

This deploys to the production project by default. Set `SUPABASE_PROJECT_REF`
to override:
```bash
SUPABASE_PROJECT_REF=qjeutitqgdsasccxfxdy ./scripts/deploy-agent-settings-direct.sh
```

### Option C: Deploy to both at once

```bash
export DOIT_DEV_SERVICE_ROLE_KEY="eyJ..."
export DOIT_PROD_SERVICE_ROLE_KEY="eyJ..."
./scripts/deploy-all-projects.sh
```

## Migration SQL

If you prefer to apply migrations manually, run this in Supabase Dashboard > SQL Editor:

```sql
alter table agent_model_settings
    alter column provider type text using provider::text;

alter table agent_model_settings
    add column base_url text;

drop type if exists agent_model_provider;
```

## Verification

After deployment, the function should return HTTP 401 (not 404) when called
without auth:

```bash
curl -X POST "https://nportxmsauhezjdubsma.supabase.co/functions/v1/agent-settings" \
  -H "Content-Type: application/json" \
  -d '{"action":"get"}'
# Expected: HTTP 401 (JWT verification active)
# NOT: HTTP 404 (function not found)
```
