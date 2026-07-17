#!/usr/bin/env bash
# deploy-agent-settings-direct.sh
#
# Deploy the agent-settings Edge Function using the Supabase Management API
# directly via curl (no CLI dependency) — works from any machine.
#
# Prerequisites:
#   A Supabase Personal Access Token (PAT) with Management API access to
#   the project's organization.
#
#   Get a PAT: https://supabase.com/dashboard/account/tokens
#   Create one with scope "api" — it starts with "sbp_".
#
# Usage:
#   export SUPABASE_PAT="sbp_abc123..."
#   SUPABASE_PROJECT_REF=nportxmsauhezjdubsma ./scripts/deploy-agent-settings-direct.sh
#
# Default: deploys to production project (nportxmsauhezjdubsma)
#
# What it does:
#   1. Creates/updates the agent-settings Edge Function via Management API
#   2. Uploads the function code
#   3. Sets required secrets (SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY)
#   4. Verifies the function is live
#
# Migrations must still be applied separately via the Dashboard SQL Editor
# or the Supabase CLI (supabase db push --project-ref <ref>).

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ---- Config ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SUPABASE_PAT="${SUPABASE_PAT:-}"
PROJECT_REF="${SUPABASE_PROJECT_REF:-nportxmsauhezjdubsma}"
SUPABASE_URL="https://${PROJECT_REF}.supabase.co"
API_BASE="https://api.supabase.com/v1"

# Per-project anon keys (public, safe to embed in scripts)
declare -A ANON_KEYS
ANON_KEYS[nportxmsauhezjdubsma]="sb_publishable_Y_ug6gCljcKuPnst_s1TMw_oZ5BosqD"
ANON_KEYS[qjeutitqgdsasccxfxdy]="sb_publishable__PwyGaVjSxKhMKb2HgE3EQ_Id9qCEGJ"

ANON_KEY="${ANON_KEYS[$PROJECT_REF]:-}"
SERVICE_ROLE_KEY="${DOIT_SUPABASE_SERVICE_ROLE_KEY:-}"

FUNCTION_SRC="$PROJECT_DIR/supabase/functions/agent-settings/index.ts"
FUNCTION_SLUG="agent-settings"

info "=== PLY-309: Direct Deploy agent-settings Edge Function ==="
info "Project: $PROJECT_REF ($SUPABASE_URL)"
echo ""

# ---- Pre-flight ----
if [ -z "$SUPABASE_PAT" ]; then
    error "SUPABASE_PAT is not set."
    error "Create a PAT at https://supabase.com/dashboard/account/tokens"
    error "Then re-run: export SUPABASE_PAT=sbp_xxx && $0"
    exit 1
fi

if [ ! -f "$FUNCTION_SRC" ]; then
    error "Function source not found: $FUNCTION_SRC"
    exit 1
fi

if [ -z "$ANON_KEY" ]; then
    error "Unknown project ref: $PROJECT_REF"
    error "Add an anon key for this project to the ANON_KEYS map in this script."
    exit 1
fi

if [ -z "$SERVICE_ROLE_KEY" ]; then
    warn "DOIT_SUPABASE_SERVICE_ROLE_KEY not set. Not needed — the function uses"
    warn "  user-level auth with RLS (migration #44). Secrets step will be skipped."
fi

# Verify PAT works
info "Verifying PAT access..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $SUPABASE_PAT" \
    "$API_BASE/projects" 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
    error "PAT lacks Management API access (HTTP $HTTP_CODE)."
    error "Create a new PAT at https://supabase.com/dashboard/account/tokens"
    error "Make sure it has access to the organization that owns $PROJECT_REF."
    exit 1
elif [ "$HTTP_CODE" = "200" ]; then
    info "  PAT is valid."
else
    warn "  Unexpected HTTP $HTTP_CODE — will try anyway."
fi

# ---- Step 1: Create or update the function ----
echo ""
info "[1/4] Creating/updating Edge Function metadata..."

# Upsert via PATCH (or create via POST if first time)
UPDATED=false
CREATE_RESP=$(curl -s -w "\n%{http_code}" -X PATCH \
    "$API_BASE/projects/$PROJECT_REF/functions/$FUNCTION_SLUG" \
    -H "Authorization: Bearer $SUPABASE_PAT" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$FUNCTION_SLUG\",\"slug\":\"$FUNCTION_SLUG\",\"verify_jwt\":true,\"import_map\":false}" 2>/dev/null)

CREATE_CODE=$(echo "$CREATE_RESP" | tail -1)
CREATE_BODY=$(echo "$CREATE_RESP" | head -n -1)

if [ "$CREATE_CODE" = "200" ] || [ "$CREATE_CODE" = "201" ]; then
    info "  Function updated: $CREATE_BODY" | head -1
    UPDATED=true
elif echo "$CREATE_BODY" | grep -q "not found"; then
    info "  Function doesn't exist yet, creating..."
    CREATE_RESP2=$(curl -s -w "\n%{http_code}" -X POST \
        "$API_BASE/projects/$PROJECT_REF/functions" \
        -H "Authorization: Bearer $SUPABASE_PAT" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$FUNCTION_SLUG\",\"slug\":\"$FUNCTION_SLUG\",\"verify_jwt\":true,\"import_map\":false}" 2>/dev/null)
    CREATE_CODE2=$(echo "$CREATE_RESP2" | tail -1)
    if [ "$CREATE_CODE2" = "200" ] || [ "$CREATE_CODE2" = "201" ]; then
        info "  Function created."
        UPDATED=true
    else
        error "  Create failed (HTTP $CREATE_CODE2):"
        echo "$CREATE_RESP2" | head -n -1
        exit 1
    fi
else
    error "  Upsert failed (HTTP $CREATE_CODE):"
    echo "$CREATE_BODY"
    exit 1
fi

# ---- Step 2: Upload function code ----
echo ""
info "[2/4] Uploading function code..."
FUNCTION_CODE=$(cat "$FUNCTION_SRC" | python3 -c "import sys,base64,json; print(json.dumps({'code': base64.b64encode(sys.stdin.read().encode()).decode()}))")

UPLOAD_RESP=$(curl -s -w "\n%{http_code}" -X POST \
    "$API_BASE/projects/$PROJECT_REF/functions/$FUNCTION_SLUG/body" \
    -H "Authorization: Bearer $SUPABASE_PAT" \
    -H "Content-Type: application/json" \
    -d "$FUNCTION_CODE" 2>/dev/null)

UPLOAD_CODE=$(echo "$UPLOAD_RESP" | tail -1)
if [ "$UPLOAD_CODE" = "200" ] || [ "$UPLOAD_CODE" = "201" ]; then
    info "  Code uploaded successfully."
else
    error "  Upload failed (HTTP $UPLOAD_CODE):"
    echo "$UPLOAD_RESP" | head -n -1
    exit 1
fi

# ---- Step 3: Set secrets via Management API ----
echo ""
info "[3/4] Setting Edge Function secrets..."

if [ -z "$SERVICE_ROLE_KEY" ]; then
    # Function now uses user-level auth via RLS (migration #44).
    # Only set URL and anon key — the service_role key is no longer needed.
    warn "  No SERVICE_ROLE_KEY — setting only SUPABASE_URL + SUPABASE_ANON_KEY."
    SECRETS_PAYLOAD="{
        \"secrets\": [
            {\"name\":\"SUPABASE_URL\",\"value\":\"$SUPABASE_URL\"},
            {\"name\":\"SUPABASE_ANON_KEY\",\"value\":\"$ANON_KEY\"}
        ]
    }"
else
    SECRETS_PAYLOAD="{
        \"secrets\": [
            {\"name\":\"SUPABASE_URL\",\"value\":\"$SUPABASE_URL\"},
            {\"name\":\"SUPABASE_ANON_KEY\",\"value\":\"$ANON_KEY\"},
            {\"name\":\"SUPABASE_SERVICE_ROLE_KEY\",\"value\":\"$SERVICE_ROLE_KEY\"}
        ]
    }"
fi

# Use the payload variable we just built
SECRETS_RESP=$(curl -s -w "\n%{http_code}" -X POST \
    "$API_BASE/projects/$PROJECT_REF/secrets" \
    -H "Authorization: Bearer $SUPABASE_PAT" \
    -H "Content-Type: application/json" \
    -d "$SECRETS_PAYLOAD" 2>/dev/null)

SECRETS_CODE=$(echo "$SECRETS_RESP" | tail -1)
if [ "$SECRETS_CODE" = "200" ] || [ "$SECRETS_CODE" = "201" ]; then
    info "  Secrets set successfully."
elif [ "$SECRETS_CODE" = "204" ]; then
    info "  Secrets set successfully (no content)."
else
    warn "  Secrets may have failed (HTTP $SECRETS_CODE):"
    echo "$SECRETS_RESP" | head -n -1
    warn "  Continuing — the function may still work if secrets are already set."
fi

# ---- Step 4: Verify ----
echo ""
info "[4/4] Verifying agent-settings endpoint..."
VERIFY_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    "$SUPABASE_URL/functions/v1/agent-settings" \
    -H "Content-Type: application/json" \
    -d '{"action":"get"}' 2>/dev/null || echo "000")

echo ""
if [ "$VERIFY_CODE" = "401" ]; then
    echo -e "  ${GREEN}✅ Function is live (HTTP 401 — JWT verification active)${NC}"
    echo ""
    info "=== DEPLOYMENT SUCCESSFUL ==="
    echo ""
    echo "  Next steps:"
    echo "  1. Apply migration #43 in Supabase Dashboard > SQL Editor"
    echo "     SQL file: supabase/migrations/20240601000043_self_hosted_provider_base_url.sql"
    echo "  2. Build and run the iOS app"
    echo "  3. Go to Settings > Model — the red 404 error should be gone"
    echo "  4. Self-managed providers with base_url should save successfully"
elif [ "$VERIFY_CODE" = "200" ]; then
    echo -e "  ${GREEN}✅ Function is live (HTTP 200)${NC}"
elif [ "$VERIFY_CODE" = "404" ]; then
    echo -e "  ${RED}❌ Function NOT found (HTTP 404) — deploy may have failed${NC}"
    exit 1
else
    echo -e "  ${YELLOW}⚠️ Unexpected status: HTTP $VERIFY_CODE${NC}"
fi
