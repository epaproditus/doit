#!/usr/bin/env bash
# verify-deploy-status.sh
#
# Check deployment status of agent-settings Edge Function on both
# dev and production Supabase projects. Provides guidance for next steps.
#
# Usage:
#   ./scripts/verify-deploy-status.sh

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

check_project() {
    local label="$1" ref="$2"
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        "https://${ref}.supabase.co/functions/v1/agent-settings" \
        -H "Content-Type: application/json" \
        -d '{"action":"get"}' --max-time 10 2>/dev/null || echo "000")

    case "$status" in
        401)
            echo -e "  ${GREEN}LIVE${NC} (HTTP 401 - JWT verification active)"
            return 0
            ;;
        200)
            echo -e "  ${GREEN}LIVE${NC} (HTTP 200)"
            return 0
            ;;
        404)
            echo -e "  ${RED}NOT DEPLOYED${NC} (HTTP 404)"
            return 1
            ;;
        *)
            echo -e "  ${YELLOW}UNKNOWN${NC} (HTTP ${status})"
            return 2
            ;;
    esac
}

echo ""
echo "=============================================="
echo "  agent-settings Edge Function Status"
echo "=============================================="
echo ""

DEV_REF="qjeutitqgdsasccxfxdy"
PROD_REF="nportxmsauhezjdubsma"

echo "Dev project  (${DEV_REF}):"
check_project "dev" "$DEV_REF"
echo ""

echo "Prod project (${PROD_REF}):"
if check_project "prod" "$PROD_REF"; then
    echo ""
    echo "  Production function is live. PLY-309 is resolved!"
    echo "  The iOS app should no longer show the 404 error."
else
    echo ""
    echo "  Production function is NOT deployed."
    echo ""
    echo "  === TO DEPLOY ==="
    echo ""
    echo "  Option A -- Provide a Supabase PAT (easiest):"
    echo "    1. Get a PAT from https://supabase.com/dashboard/account/tokens"
    echo "       (Create one with Management API access to the project's org)"
    echo "    2. Run: SUPABASE_PAT=sbp_xxx make deploy-prod"
    echo ""
    echo "  Option B -- Deploy via Dashboard (no CLI needed):"
    echo "    1. Open https://supabase.com/dashboard/project/${PROD_REF}"
    echo "    2. Edge Functions > Create > agent-settings"
    echo "    3. Paste code from supabase/functions/agent-settings/index.ts"
    echo "    4. Set secrets: SUPABASE_URL, SUPABASE_ANON_KEY"
    echo "    5. SQL Editor > Run migrations #43 and #44"
    echo ""
    echo "  Option C -- Use GitHub Actions:"
    echo "    1. Add SUPABASE_ACCESS_TOKEN to repo secrets"
    echo "    2. Go to Actions > 'Deploy Edge Functions' > Run workflow"
    echo "    3. Check 'Apply pending migrations'"
    echo ""
    echo "  After deployment, run this script again to verify."
fi

echo ""
echo "=============================================="
echo "  Verify with a test call"
echo "=============================================="
echo ""
echo "  After deploying, the function should return HTTP 401 (not 404):"
echo ""
echo "    curl -s -o /dev/null -w '%{http_code}' -X POST \\"
echo "      https://${PROD_REF}.supabase.co/functions/v1/agent-settings \\"
echo "      -H 'Content-Type: application/json' \\"
echo "      -d '{\"action\":\"get\"}'"
echo ""
echo "  Expected: 401"
echo ""
