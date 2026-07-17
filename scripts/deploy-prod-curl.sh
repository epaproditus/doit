#!/usr/bin/env bash
# deploy-prod-curl.sh
#
# Deploy agent-settings Edge Function to production using curl + Management API.
# No Supabase CLI needed — just curl and a valid PAT.
#
# Usage:
#   1. Get a Supabase PAT:
#      https://supabase.com/dashboard/account/tokens
#      Create a token with access to the nportxmsauhezjdubsma project's org.
#
#   2. Run:
#      export SUPABASE_PAT=sbp_your_valid_token_here
#      ./scripts/deploy-prod-curl.sh
#
#   3. Or one-liner:
#      SUPABASE_PAT=sbp_xxx ./scripts/deploy-prod-curl.sh
#
# What it does:
#   - Bundles the function source as a multipart upload to the Management API
#   - Creates or updates the agent-settings function on the production project
#   - Verifies the endpoint responds (expects 401 = deployed with JWT verification)
#
# Prerequisites:
#   - curl
#   - A Supabase PAT with Management API access to the project's org

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
step()  { echo -e "${BLUE}[STEP]${NC} $*"; }

PROJECT_REF="nportxmsauhezjdubsma"
FUNCTION_NAME="agent-settings"
ENTRYPOINT="index.ts"
FUNCTION_SOURCE="supabase/functions/${FUNCTION_NAME}/${ENTRYPOINT}"

cd "$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"

echo ""
echo "================================================================"
echo "  Deploy ${FUNCTION_NAME} → PRODUCTION"
echo "  Project: ${PROJECT_REF}"
echo "================================================================"
echo ""

# --- Check prerequisites ---
step "Checking prerequisites..."

if ! command -v curl &>/dev/null; then
    error "curl is required but not installed."
    exit 1
fi

PAT="${SUPABASE_PAT:-}"
if [ -z "$PAT" ]; then
    error "SUPABASE_PAT is not set."
    echo ""
    echo "  Get a PAT from: https://supabase.com/dashboard/account/tokens"
    echo ""
    echo "  Make sure the PAT has Management API access to the Supabase"
    echo "  organization that owns the '${PROJECT_REF}' project."
    echo ""
    echo "  Then run: export SUPABASE_PAT=sbp_xxx && $0"
    exit 1
fi

if [ ! -f "$FUNCTION_SOURCE" ]; then
    error "Function source not found: ${FUNCTION_SOURCE}"
    echo "  Make sure you're in the doit project root."
    exit 1
fi

info "All prerequisites met."
echo ""

# --- Validate PAT ---
step "Validating PAT..."

VALIDATE_RESP=$(curl -s -o /dev/null -w "%{http_code}" \
    "https://api.supabase.com/v1/projects/${PROJECT_REF}/functions" \
    -H "Authorization: Bearer ${PAT}")

if [ "$VALIDATE_RESP" = "401" ]; then
    error "PAT is invalid or lacks Management API access to project ${PROJECT_REF}."
    echo ""
    echo "  The PAT must have Management API access to the Supabase"
    echo "  organization that owns this project."
    echo ""
    echo "  Check your PAT at: https://supabase.com/dashboard/account/tokens"
    exit 1
elif [ "$VALIDATE_RESP" = "200" ]; then
    info "PAT is valid. Project accessible."
elif [ "$VALIDATE_RESP" = "404" ]; then
    error "Project '${PROJECT_REF}' not found. Check the project ref."
    exit 1
else
    warn "Unexpected response (HTTP ${VALIDATE_RESP}). Proceeding anyway..."
fi
echo ""

# --- Deploy function ---
step "Deploying ${FUNCTION_NAME} function..."

DEPLOY_RESP=$(curl -s --request POST \
    --url "https://api.supabase.com/v1/projects/${PROJECT_REF}/functions/deploy?slug=${FUNCTION_NAME}" \
    --header "Authorization: Bearer ${PAT}" \
    --header "content-type: multipart/form-data" \
    --form "metadata={\"entrypoint_path\": \"${ENTRYPOINT}\", \"name\": \"${FUNCTION_NAME}\"}" \
    --form "file=@${FUNCTION_SOURCE}" 2>&1)

echo "$DEPLOY_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print('  ID:', d.get('id','?')); print('  Name:', d.get('name','?')); print('  Status:', d.get('status','?')); print('  Created:', d.get('created_at','?'))" 2>/dev/null || echo "  Response: $DEPLOY_RESP"

if echo "$DEPLOY_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null | grep -q .; then
    info "Function deployed successfully!"
else
    if echo "$DEPLOY_RESP" | grep -q "401\|Unauthorized"; then
        error "Authorization failed. The PAT doesn't have access to this project."
        exit 1
    elif echo "$DEPLOY_RESP" | grep -q "422\|already exists\|duplicate"; then
        warn "Function already exists. Update verified below."
    else
        error "Deploy failed: $(echo "$DEPLOY_RESP" | head -c 200)"
        exit 1
    fi
fi
echo ""

# --- Verify ---
step "Verifying deployment..."
sleep 3

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    "https://${PROJECT_REF}.supabase.co/functions/v1/${FUNCTION_NAME}" \
    -H "Content-Type: application/json" \
    -d '{"action":"get"}' 2>/dev/null || echo "000")

echo ""
if [ "$HTTP_CODE" = "401" ]; then
    echo -e "  ${GREEN}✅ Function is LIVE (HTTP 401 — JWT verification active)${NC}"
    echo ""
    echo "  Production deployment complete!"
    echo "  The iOS app will no longer show the 404 error for agent-settings."
    echo ""
    echo "  === DEPLOYMENT SUCCESSFUL ==="
elif [ "$HTTP_CODE" = "200" ]; then
    echo -e "  ${GREEN}✅ Function is LIVE (HTTP 200)${NC}"
    echo ""
    echo "  === DEPLOYMENT SUCCESSFUL ==="
elif [ "$HTTP_CODE" = "404" ]; then
    echo -e "  ${RED}❌ Function NOT found (HTTP 404) — deploy may have failed${NC}"
    exit 1
else
    echo -e "  ${YELLOW}⚠️  Unexpected status: HTTP ${HTTP_CODE}${NC}"
    echo "  The function may still be deploying. Check the Supabase Dashboard:"
    echo "  https://supabase.com/dashboard/project/${PROJECT_REF}/functions"
fi
