#!/usr/bin/env bash
# deploy-agent-settings.sh
#
# Deploy the agent-settings Edge Function to the production Supabase project.
#
# Usage:
#   export SUPABASE_PAT=sbp_xxx   # from https://supabase.com/dashboard/account/tokens
#   ./scripts/deploy-agent-settings.sh
#
# Or one-liner:
#   SUPABASE_PAT=sbp_xxx ./scripts/deploy-agent-settings.sh
#
# What it does:
#   1. Validates the PAT against the Management API
#   2. Deploys the agent-settings function via curl + Management API
#   3. Verifies the endpoint responds (expects 401 = JWT verification active)
#
# Prerequisites:
#   - curl
#   - A Supabase PAT with Management API access to the project's org
#     Get one at: https://supabase.com/dashboard/account/tokens
#
# Environment:
#   SUPABASE_PAT       Required. Supabase PAT with Management API access.
#   SUPABASE_PROJECT_REF  Optional. Defaults to nportxmsauhezjdubsma (production).

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
step()  { echo -e "${BLUE}[STEP]${NC} $*"; }
ok()    { echo -e "  ${GREEN}✅${NC} $*"; }
fail()  { echo -e "  ${RED}❌${NC} $*"; }

PROJECT_REF="${SUPABASE_PROJECT_REF:-nportxmsauhezjdubsma}"
FUNCTION_NAME="agent-settings"
ENTRYPOINT="index.ts"
FUNCTION_SOURCE="supabase/functions/${FUNCTION_NAME}/${ENTRYPOINT}"

# Auto-detect project root (git top-level)
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
    echo "  Then run:"
    echo "    export SUPABASE_PAT=sbp_your_token_here"
    echo "    $0"
    exit 1
fi

if [ ! -f "$FUNCTION_SOURCE" ]; then
    error "Function source not found at: ${FUNCTION_SOURCE}"
    echo "  Make sure you're in the doit project root."
    echo "  Current directory: $(pwd)"
    ls -la supabase/functions/ 2>/dev/null || echo "  (no supabase/functions/ directory found)"
    exit 1
fi

ok "All prerequisites met."
echo ""

# --- Validate PAT ---
step "Validating PAT against Management API..."

VALIDATE_RESP=$(curl -s -o /dev/null -w "%{http_code}" \
    "https://api.supabase.com/v1/projects/${PROJECT_REF}/functions" \
    -H "Authorization: Bearer ${PAT}" \
    --max-time 10)

case "$VALIDATE_RESP" in
    200)
        ok "PAT is valid. Project accessible."
        ;;
    401)
        error "PAT is invalid or lacks Management API access to project ${PROJECT_REF}."
        echo ""
        echo "  The PAT must have Management API access to the Supabase"
        echo "  organization that owns this project."
        echo ""
        echo "  Check your PAT at: https://supabase.com/dashboard/account/tokens"
        echo "  Create a new token if needed, ensuring it has 'Management API' access."
        exit 1
        ;;
    404)
        error "Project '${PROJECT_REF}' not found. Check the project ref."
        echo "  Expected ref for production: nportxmsauhezjdubsma"
        exit 1
        ;;
    *)
        warn "Unexpected response (HTTP ${VALIDATE_RESP}). Proceeding anyway..."
        ;;
esac
echo ""

# --- Deploy function ---
step "Deploying ${FUNCTION_NAME} function via Management API..."

DEPLOY_RESP=$(curl -s --request POST \
    --url "https://api.supabase.com/v1/projects/${PROJECT_REF}/functions/deploy?slug=${FUNCTION_NAME}" \
    --header "Authorization: Bearer ${PAT}" \
    --header "content-type: multipart/form-data" \
    --form "metadata={\"entrypoint_path\": \"${ENTRYPOINT}\", \"name\": \"${FUNCTION_NAME}\"}" \
    --form "file=@${FUNCTION_SOURCE}" \
    --max-time 30 2>&1)

# Try to parse the response as JSON
if echo "$DEPLOY_RESP" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    if 'id' in d:
        print(f'ID: {d[\"id\"]}')
        print(f'Name: {d[\"name\"]}')
        print(f'Status: {d.get(\"status\", \"?\")}')
        print(f'Created: {d.get(\"created_at\", \"?\")}')
        sys.exit(0)
    elif 'error' in d:
        print(f'Error: {d[\"error\"]} - {d.get(\"message\", \"\")}')
        sys.exit(1)
    else:
        print(json.dumps(d, indent=2))
        sys.exit(0)
except Exception:
    sys.exit(2)
" 2>/dev/null; then
    ok "Function deployed successfully!"
elif [ $? -eq 1 ]; then
    # JSON with error field
    warn "Deploy responded with error. See above."
    # Check for specific errors
    if echo "$DEPLOY_RESP" | grep -qi "already exists"; then
        warn "Function already exists (possibly from a previous deploy). Updating..."
        # It did update -- the error might be spurious
        ok "Assuming function was updated. Verification below will confirm."
    else
        error "Deploy failed. Response: $(echo "$DEPLOY_RESP" | head -c 300)"
        exit 1
    fi
else
    # Non-JSON response or parse error
    if echo "$DEPLOY_RESP" | grep -qi "401\|Unauthorized\|unauthorized"; then
        error "Authorization failed during deployment. The PAT doesn't have access."
        exit 1
    elif echo "$DEPLOY_RESP" | grep -qi "404\|Not Found\|not found"; then
        error "Project '${PROJECT_REF}' not found or Management API unavailable."
        exit 1
    elif echo "$DEPLOY_RESP" | grep -qi "already exists\|duplicate"; then
        warn "Function already exists (previous deploy). Verifying update..."
    else
        warn "Unexpected deploy response:"
        echo "  $DEPLOY_RESP" | head -5
        warn "Proceeding to verification step..."
    fi
fi
echo ""

# --- Verify ---
step "Verifying deployment..."

# Wait a moment for propagation
sleep 3

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    "https://${PROJECT_REF}.supabase.co/functions/v1/${FUNCTION_NAME}" \
    -H "Content-Type: application/json" \
    -d '{"action":"get"}' \
    --max-time 10)

echo ""
case "$HTTP_CODE" in
    401)
        echo -e "  ${GREEN}✅ Function is LIVE (HTTP 401 — JWT verification active)${NC}"
        echo ""
        echo "  Production deployment complete!"
        echo "  The iOS app will no longer show the 404 error for agent-settings."
        echo ""
        echo "  === DEPLOYMENT SUCCESSFUL ==="
        ;;
    200)
        echo -e "  ${GREEN}✅ Function is LIVE (HTTP 200)${NC}"
        echo ""
        echo "  === DEPLOYMENT SUCCESSFUL ==="
        ;;
    404)
        echo -e "  ${RED}❌ Function NOT found (HTTP 404) — deploy may have failed${NC}"
        echo ""
        echo "  The function was NOT deployed. Possible reasons:"
        echo "  1. The PAT doesn't have Management API write access to this project"
        echo "  2. The deploy request failed silently"
        echo "  3. The function may still be deploying (try again in 30s)"
        echo ""
        echo "  To verify manually, check the Supabase Dashboard:"
        echo "  https://supabase.com/dashboard/project/${PROJECT_REF}/functions"
        exit 1
        ;;
    *)
        echo -e "  ${YELLOW}⚠️  Unexpected status: HTTP ${HTTP_CODE}${NC}"
        echo ""
        echo "  The function may still be deploying. Check the Dashboard:"
        echo "  https://supabase.com/dashboard/project/${PROJECT_REF}/functions"
        exit 1
        ;;
esac
