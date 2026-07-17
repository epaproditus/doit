#!/usr/bin/env bash
# fix-agent-settings-deploy.sh
#
# ONE-SHOT fix for PLY-309: Deploy the updated agent-settings Edge Function
# and apply migration #43 (base_url column + provider text).
#
# Run this ONCE from your Mac after pulling latest main.
#
# Prerequisites:
#   1. Supabase CLI:  npm install -g supabase
#   2. Supabase login: supabase login   (opens browser to get a PAT)
#   3. Pull latest:    git pull origin main
#
# Usage:
#   cd ~/path/to/doit
#   ./scripts/fix-agent-settings-deploy.sh
#
# What it does:
#   - Deploys agent-settings to the iOS project (qjeutitqgdsasccxfxdy)
#     with the latest PLY-308 base_url support
#   - Applies migration 20240601000043 (provider→text, adds base_url column)
#   - Verifies the function responds correctly
#
# If you want to also deploy to the production connector project:
#   SUPABASE_PROJECT_REF=nportxmsauhezjdubsma ./scripts/fix-agent-settings-deploy.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Which project?
PROJECT_REF="${SUPABASE_PROJECT_REF:-qjeutitqgdsasccxfxdy}"
SUPABASE_URL="https://${PROJECT_REF}.supabase.co"
ANON_KEY="sb_publishable__PwyGaVjSxKhMKb2HgE3EQ_Id9qCEGJ"

if [ "$PROJECT_REF" = "nportxmsauhezjdubsma" ]; then
  ANON_KEY="sb_publishable_Y_ug6gCljcKuPnst_s1TMw_oZ5BosqD"
fi

info "=== PLY-309 Fix: Deploy agent-settings + migration ==="
info "Project: $PROJECT_REF ($SUPABASE_URL)"
echo ""

# 1. Check prerequisites
if ! command -v supabase &>/dev/null; then
  error "Supabase CLI not found. Install: npm install -g supabase"
  exit 1
fi

# 2. Check we're on latest main
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "main" ]; then
  warn "You're on branch '$CURRENT_BRANCH', not main. Deploying anyway..."
fi

# 3. Link the project
info "Linking Supabase project..."
if supabase link --project-ref "$PROJECT_REF" 2>&1; then
  info "Project linked."
else
  # Try with database password fallback
  if [ -n "${SUPABASE_DB_PASSWORD:-}" ]; then
    info "Trying database password link..."
    supabase link --project-ref "$PROJECT_REF" --password "$SUPABASE_DB_PASSWORD" 2>&1
  else
    error "Link failed. Make sure you're logged in via 'supabase login'"
    error "Or set SUPABASE_DB_PASSWORD (from Supabase Dashboard > Settings > Database)"
    exit 1
  fi
fi

# 4. Apply migration #43
echo ""
info "Applying migration: provider->text, add base_url column..."
if supabase db push --project-ref "$PROJECT_REF" 2>&1; then
  info "Migration applied successfully."
else
  warn "db push failed. Trying via direct SQL..."
  echo ""
  warn "Run this SQL in Supabase Dashboard > SQL Editor:"
  warn "--------------------------------------------------"
  cat "$PROJECT_DIR/supabase/migrations/20240601000043_self_hosted_provider_base_url.sql"
  warn "--------------------------------------------------"
fi

# 5. Deploy the function
echo ""
info "Deploying agent-settings Edge Function..."
if supabase functions deploy agent-settings --project-ref "$PROJECT_REF" 2>&1; then
  info "Function deployed successfully."
else
  error "Function deploy failed. Check Supabase CLI access."
  exit 1
fi

# 6. Verify
echo ""
info "Verifying agent-settings endpoint..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "$SUPABASE_URL/functions/v1/agent-settings" \
  -H "Content-Type: application/json" \
  -d '{"action":"get"}' 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "401" ]; then
  echo -e "  ${GREEN}✅ Function is live (HTTP 401 — JWT verification active)${NC}"
elif [ "$HTTP_CODE" = "200" ]; then
  echo -e "  ${GREEN}✅ Function is live (HTTP 200)${NC}"
elif [ "$HTTP_CODE" = "404" ]; then
  echo -e "  ${RED}❌ Function NOT found (HTTP 404)${NC}"
  exit 1
else
  echo -e "  ${YELLOW}⚠️ Unexpected: HTTP $HTTP_CODE${NC}"
fi

# 7. Verify base_url column exists
echo ""
info "Verifying base_url column in DB..."
VERIFY_TOKEN=$(curl -s -X POST "$SUPABASE_URL/auth/v1/signup" \
  -H "Content-Type: application/json" \
  -H "apikey: $ANON_KEY" \
  -d '{}' | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null)

if [ -n "$VERIFY_TOKEN" ]; then
  COLUMN_CHECK=$(curl -s -X GET "$SUPABASE_URL/rest/v1/agent_model_settings?select=base_url&limit=1" \
    -H "Authorization: Bearer $VERIFY_TOKEN" \
    -H "apikey: $ANON_KEY" \
    -w "\nHTTP_CODE:%{http_code}")
  
  HTTP_CODE=$(echo "$COLUMN_CHECK" | grep "HTTP_CODE:" | cut -d: -f2)
  if [ "$HTTP_CODE" = "200" ]; then
    echo -e "  ${GREEN}✅ base_url column exists${NC}"
  else
    echo -e "  ${YELLOW}⚠️  base_url column not accessible (HTTP $HTTP_CODE)${NC}"
  fi
else
  echo -e "  ${YELLOW}⚠️  Could not verify (auth rate limited)${NC}"
fi

echo ""
info "=== Done ==="
echo ""
echo "Next: Build and run the iOS app. Go to Settings > Model."
echo "The red error should be gone. Self-managed providers with base_url should save."
