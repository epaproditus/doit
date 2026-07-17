#!/usr/bin/env bash
# deploy-prod.sh — Deploy agent-settings Edge Function to PRODUCTION
#
# Usage:
#   export SUPABASE_PAT="sbp_xyz..."   # from https://supabase.com/dashboard/account/tokens
#   ./scripts/deploy-prod.sh
#
# What it does:
#   1. Deploys agent-settings function to nportxmsauhezjdubsma (production)
#   2. No secrets needed — function uses auto-injected SUPABASE_URL + SUPABASE_ANON_KEY
#   3. Verifies the endpoint responds (expects 401 = deployed, needs auth)
#
# Prerequisites:
#   - supabase CLI (npm install -g supabase)
#   - A Supabase PAT with Management API access to the project's org
#
# Quick start from Mac:
#   npm install -g supabase && supabase login
#   cd ~/path/to/doit && git pull && ./scripts/deploy-prod.sh

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

PROJECT_REF="nportxmsauhezjdubsma"
FUNCTION="agent-settings"

cd "$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"

info "=== Deploy agent-settings to PRODUCTION ==="
info "Project: $PROJECT_REF"
echo ""

# ---- Step 1: Link ----
info "[1/3] Linking to production project..."
if supabase link --project-ref "$PROJECT_REF" 2>/dev/null; then
    info "  Linked successfully."
else
    warn "  supabase link failed. Trying with --password flag..."
    warn "  (You may need to provide a DB password for direct linking)"
    warn "  Run: supabase link --project-ref $PROJECT_REF --password YOUR_DB_PASSWORD"
    exit 1
fi

# ---- Step 2: Deploy ----
info "[2/3] Deploying $FUNCTION function..."
supabase functions deploy "$FUNCTION" --project-ref "$PROJECT_REF" --use-api
info "  Deploy command completed."

# ---- Step 3: Verify ----
info "[3/3] Verifying endpoint..."
sleep 3
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    "https://$PROJECT_REF.supabase.co/functions/v1/$FUNCTION" \
    -H "Content-Type: application/json" \
    -d '{"action":"get"}' 2>/dev/null || echo "000")

echo ""
if [ "$HTTP_CODE" = "401" ]; then
    echo -e "  ${GREEN}✅ Function is LIVE (HTTP 401 — JWT verification active)${NC}"
    echo ""
    echo "  Production deployment complete!"
    echo "  The iOS app will no longer show the 404 error."
elif [ "$HTTP_CODE" = "404" ]; then
    echo -e "  ${RED}❌ Function NOT found (HTTP 404) — deploy may have failed${NC}"
    exit 1
else
    echo -e "  ${YELLOW}⚠️  Unexpected status: HTTP $HTTP_CODE${NC}"
    echo "  Function may still be deploying. Check the Supabase Dashboard."
fi
