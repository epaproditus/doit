#!/usr/bin/env bash
# deploy-agent-settings.sh
#
# Deploy the agent-settings Edge Function and apply the pending database
# migration for self-hosted provider support (base_url column).
#
# Prerequisites:
#   - Supabase CLI installed (brew install supabase/tap/supabase)
#   - Logged in: supabase login
#   - Access to the Supabase project nportxmsauhezjdubsma
#   - DOIT_SUPABASE_SERVICE_ROLE_KEY set (from Supabase Dashboard > Settings > API)
#
# Usage:
#   export DOIT_SUPABASE_SERVICE_ROLE_KEY=eyJ...your_service_role_key
#   ./scripts/deploy-agent-settings.sh
#
# What this does:
#   1. Links to the Supabase project
#   2. Sets required Edge Function secrets
#   3. Applies migration 20240601000043_self_hosted_provider_base_url.sql
#   4. Deploys the agent-settings Edge Function
#   5. Verifies the function responds correctly

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SUPABASE_PROJECT_REF="nportxmsauhezjdubsma"
SUPABASE_URL="https://${SUPABASE_PROJECT_REF}.supabase.co"

echo "=== PLY-309: Deploy agent-settings Edge Function ==="
echo ""

# --- Step 1: Link the project ---
echo ">> Step 1/5: Linking Supabase project..."
cd "$PROJECT_DIR"
supabase link --project-ref "$SUPABASE_PROJECT_REF"
echo "   Done."
echo ""

# --- Step 2: Set Edge Function secrets ---
echo ">> Step 2/5: Setting Edge Function secrets..."
SERVICE_ROLE_KEY="${DOIT_SUPABASE_SERVICE_ROLE_KEY:-}"

if [ -z "$SERVICE_ROLE_KEY" ]; then
    echo "   ERROR: DOIT_SUPABASE_SERVICE_ROLE_KEY is not set."
    echo "   Get it from: Supabase Dashboard > Settings > API > service_role key"
    echo "   Then re-run: export DOIT_SUPABASE_SERVICE_ROLE_KEY=eyJ... && $0"
    exit 1
fi

# Read the anon key from the linked project config
ANON_KEY=$(supabase secrets list --project-ref "$SUPABASE_PROJECT_REF" 2>/dev/null \
    | grep -i "supabase_anon_key" | awk '{print $NF}') || true
if [ -z "$ANON_KEY" ]; then
    ANON_KEY="sb_publishable__PwyGaVjSxKhMKb2HgE3EQ_Id9qCEGJ"
fi

supabase secrets set \
    SUPABASE_URL="$SUPABASE_URL" \
    SUPABASE_ANON_KEY="$ANON_KEY" \
    SUPABASE_SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY" \
    --project-ref "$SUPABASE_PROJECT_REF"
echo "   Done."
echo ""

# --- Step 3: Apply pending migration ---
echo ">> Step 3/5: Applying pending database migration..."
echo "   Running: supabase db push"
supabase db push --project-ref "$SUPABASE_PROJECT_REF"
echo "   Migration applied: 20240601000043_self_hosted_provider_base_url.sql"
echo "   Changes: provider column now text (not enum), base_url column added."
echo ""

# --- Step 4: Deploy the Edge Function ---
echo ">> Step 4/5: Deploying agent-settings Edge Function..."
supabase functions deploy agent-settings --project-ref "$SUPABASE_PROJECT_REF" --no-verify-jwt
echo "   Done."
echo ""

# --- Step 5: Verify ---
echo ">> Step 5/5: Verifying the function..."
echo "   Testing GET (without auth — expect 401, proves function is live):"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    "$SUPABASE_URL/functions/v1/agent-settings" \
    -H "Content-Type: application/json" \
    -d '{"action":"get"}')
echo "   HTTP $STATUS (expected 401 if function has JWT verification)"
echo ""

if [ "$STATUS" = "401" ]; then
    echo "   ✅ Function is live and returns 401 (expected — JWT verification active)"
    echo ""
    echo "   === VERIFICATION PASSED ==="
    echo ""
    echo "   Next steps:"
    echo "   1. Open the iOS app on device/simulator"
    echo "   2. Go to Settings > Model"
    echo "   3. Confirm no red error banner"
    echo "   4. In self-managed BYO mode, the provider/model/base_url fields"
    echo "      should load properly and accept saves"
    echo "   5. If Local.xcconfig needs updating, run:"
    echo "      export DOIT_SUPABASE_URL=$SUPABASE_URL"
    echo "      export DOIT_SUPABASE_ANON_KEY=$ANON_KEY"
    echo "      ./scripts/setup-ios-config.sh"
else
    echo "   ⚠️  Unexpected response. Verify the function manually."
    curl -s -X POST "$SUPABASE_URL/functions/v1/agent-settings" \
        -H "Content-Type: application/json" \
        -d '{"action":"get"}'
fi
