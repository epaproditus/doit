#!/usr/bin/env bash
# deploy-agent-settings-prod.sh
#
# ONE-SHOT deploy: agent-settings Edge Function to PRODUCTION.
#
# Prerequisites:
#   1. Supabase CLI installed:  npm install -g supabase
#   2. A Supabase PAT with Management API access to the project's org.
#      Get one at https://supabase.com/dashboard/account/tokens
#
# Usage:
#   export SUPABASE_PAT="sbp_xyz..."
#   ./scripts/deploy-agent-settings-prod.sh
#
# What it does:
#   1. Links to the prod project (nportxmsauhezjdubsma) via your PAT
#   2. Deploys the agent-settings Edge Function
#   3. Verifies the endpoint is live
#   4. Prints next steps for DB migrations
#
# If linking fails, your PAT may lack Management API access to this org.
# Create a new PAT at https://supabase.com/dashboard/account/tokens
# and make sure it has access to the Epaphroditus organization.

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

PROJECT_REF="nportxmsauhezjdubsma"
FUNCTION="agent-settings"

echo ""
echo "==========================================================="
echo "  PLY-309: Deploy $FUNCTION to production"
echo "  Project: $PROJECT_REF"
echo "  $(date)"
echo "==========================================================="
echo ""

# ---- Check prerequisites ----
if ! command -v supabase &>/dev/null; then
    error "Supabase CLI not found. Install: npm install -g supabase"
    exit 1
fi

if [ -z "${SUPABASE_PAT:-}" ]; then
    error "SUPABASE_PAT is not set."
    echo ""
    echo "  1. Go to https://supabase.com/dashboard/account/tokens"
    echo "  2. Create a new PAT with scope 'api'"
    echo "  3. Make sure the PAT's user has access to the Epaphroditus org"
    echo "  4. Export it:"
    echo "       export SUPABASE_PAT=\"sbp_your_new_token_here\""
    echo "  5. Re-run this script"
    echo ""
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

# ---- Link project ----
info "Linking to production project..."
supabase link --project-ref "$PROJECT_REF" 2>&1 || {
    error "Failed to link project."
    echo ""
    echo "  Your PAT ($(echo $SUPABASE_PAT | head -c 20)...) was rejected."
    echo ""
    echo "  Possible causes:"
    echo "    - PAT doesn't have access to the Epaphroditus org"
    echo "    - PAT was revoked or expired"
    echo "    - Wrong project ref ($PROJECT_REF)"
    echo ""
    echo "  CREATE A NEW PAT at https://supabase.com/dashboard/account/tokens"
    echo "  Make sure the token's user is part of the organization"
    echo "  that owns $PROJECT_REF"
    echo ""
    exit 1
}
info "Project linked successfully."

# ---- Deploy function ----
echo ""
info "Deploying $FUNCTION..."
supabase functions deploy "$FUNCTION" --project-ref "$PROJECT_REF" 2>&1 || {
    error "Deploy failed."
    exit 1
}
info "$FUNCTION deployed successfully."

# ---- Verify ----
echo ""
info "Verifying endpoint..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "https://$PROJECT_REF.supabase.co/functions/v1/$FUNCTION" \
    -H "Content-Type: application/json" \
    -d '{"action":"get"}' 2>/dev/null || echo "000")

echo ""
if [ "$HTTP_CODE" = "401" ]; then
    echo -e "  ${GREEN}LIVE (HTTP 401 — JWT verification active)${NC}"
    echo ""
    echo "==========================================================="
    echo "  DEPLOYMENT SUCCESSFUL"
    echo "==========================================================="
    echo ""
    echo "  Next steps:"
    echo "  1. Apply DB migrations in Supabase Dashboard > SQL Editor:"
    echo "     supabase/migrations/20240601000043_self_hosted_provider_base_url.sql"
    echo "     supabase/migrations/20240601000044_rls_for_user_setting_upsert.sql"
    echo ""
    echo "  2. Build and run the iOS app"
    echo "  3. Go to Settings > Model — the 404 error should be gone"
    echo ""
elif [ "$HTTP_CODE" = "200" ]; then
    echo -e "  ${GREEN}LIVE (HTTP 200)${NC}"
else
    warn "Unexpected HTTP $HTTP_CODE"
fi
