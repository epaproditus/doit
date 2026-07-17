#!/usr/bin/env bash
# PLY-309: Deploy agent-settings Edge Function with self-managed provider support
#
# Deploys the function and applies migration 00043 (base_url column).
#
# Prerequisites (pick ONE auth method):
#   A) supabase login (PAT with project access)
#   B) SUPABASE_DB_PASSWORD set (from Dashboard > Project Settings > Database)
#
# Also needs:
#   DOIT_SUPABASE_SERVICE_ROLE_KEY (from Dashboard > Settings > API)
#
# Usage:
#   export DOIT_SUPABASE_SERVICE_ROLE_KEY=eyJ...
#   export SUPABASE_DB_PASSWORD=your_db_password   # if not using PAT
#   SUPABASE_PROJECT_REF=nportxmsauhezjdubsma ./scripts/pl-309-deploy.sh
#
# Defaults to the dev project (qjeuti) if SUPABASE_PROJECT_REF unset.

set -euo pipefail

PROJECT_REF="${SUPABASE_PROJECT_REF:-qjeutitqgdsasccxfxdy}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== PLY-309: Deploy agent-settings (self-managed provider fix) ==="
echo "   Project: $PROJECT_REF"
echo ""

cd "$PROJECT_DIR"

# Step 1: Link project
echo ">> Linking project $PROJECT_REF..."
if supabase link --project-ref "$PROJECT_REF" 2>/dev/null; then
    echo "   Linked via PAT."
elif [ -n "${SUPABASE_DB_PASSWORD:-}" ]; then
    echo "   PAT failed, trying DB password..."
    supabase link --project-ref "$PROJECT_REF" --password "$SUPABASE_DB_PASSWORD"
else
    echo "   ERROR: Cannot link. Run 'supabase login' or set SUPABASE_DB_PASSWORD."
    exit 1
fi
echo ""

# Step 2: Set secrets
echo ">> Setting function secrets..."
if [ -z "${DOIT_SUPABASE_SERVICE_ROLE_KEY:-}" ]; then
    echo "   ERROR: DOIT_SUPABASE_SERVICE_ROLE_KEY not set."
    echo "   Get it from: Supabase Dashboard > Settings > API"
    exit 1
fi

# Determine anon key based on project
case "$PROJECT_REF" in
    qjeutitqgdsasccxfxdy)
        ANON_KEY="sb_publishable__PwyGaVjSxKhMKb2HgE3EQ_Id9qCEGJ"
        ;;
    nportxmsauhezjdubsma)
        echo "   WARNING: Production project anon key unknown. Set SUPABASE_ANON_KEY env var."
        ANON_KEY="${SUPABASE_ANON_KEY:-}"
        ;;
    *)
        ANON_KEY="${SUPABASE_ANON_KEY:-}"
        ;;
esac

supabase secrets set \
    SUPABASE_URL="https://${PROJECT_REF}.supabase.co" \
    SUPABASE_ANON_KEY="$ANON_KEY" \
    SUPABASE_SERVICE_ROLE_KEY="$DOIT_SUPABASE_SERVICE_ROLE_KEY" \
    --project-ref "$PROJECT_REF"
echo ""

# Step 3: Apply migration
echo ">> Applying migration 00043 (base_url column)..."
supabase db push --project-ref "$PROJECT_REF"
echo "   Done. (provider column is now text, base_url column added)"
echo ""

# Step 4: Deploy function
echo ">> Deploying agent-settings function..."
supabase functions deploy agent-settings --project-ref "$PROJECT_REF" --no-verify-jwt
echo ""

# Step 5: Verify
echo ">> Verifying..."
URL="https://${PROJECT_REF}.supabase.co"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    "$URL/functions/v1/agent-settings" \
    -H "Content-Type: application/json" \
    -d '{"action":"get"}')

if [ "$STATUS" = "401" ] || [ "$STATUS" = "200" ]; then
    echo "   ✅ Function live (HTTP $STATUS — JWT verification active)"
else
    echo "   ⚠️  HTTP $STATUS — check manually"
fi

echo ""
echo "=== Done ==="
