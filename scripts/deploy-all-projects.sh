#!/usr/bin/env bash
# deploy-all-projects.sh
#
# PLY-309: One-shot deploy of agent-settings Edge Function + migration #43
# to both the iOS dev and production Supabase projects.
#
# Run this ONCE from your Mac after pulling latest main.
#
# Prerequisites:
#   1. Supabase CLI:  npm install -g supabase
#   2. Logged in:     supabase login  (opens browser, generates a PAT)
#   3. Pull latest:   git pull origin main
#   4. Service role keys from Supabase Dashboard > Project Settings > API
#
# Usage:
#   cd ~/path/to/doit
#   export DOIT_DEV_SERVICE_ROLE_KEY=eyJ...   # from dev project
#   export DOIT_PROD_SERVICE_ROLE_KEY=eyJ...  # from production project
#   ./scripts/deploy-all-projects.sh
#
# What it does:
#   1. Deploys agent-settings to BOTH projects with the latest code
#   2. Applies migration 20240601000043 to BOTH projects
#   3. Verifies response on BOTH projects
#
# Projects:
#   DEV:  qjeutitqgdsasccxfxdy  (iOS app, debug builds)
#   PROD: nportxmsauhezjdubsma  (production connector)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")\" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ---- Configuration ----
declare -A PROJECTS
PROJECTS[dev]="qjeutitqgdsasccxfxdy"
PROJECTS[prod]="nportxmsauhezjdubsma"

declare -A ANON_KEYS
ANON_KEYS[dev]="sb_publishable__PwyGaVjSxKhMKb2HgE3EQ_Id9qCEGJ"
ANON_KEYS[prod]="sb_publishable_Y_ug6gCljcKuPnst_s1TMw_oZ5BosqD"

declare -A SERVICE_KEYS
SERVICE_KEYS[dev]="${DOIT_DEV_SERVICE_ROLE_KEY:-}"
SERVICE_KEYS[prod]="${DOIT_PROD_SERVICE_ROLE_KEY:-}"

# ---- Pre-flight checks ----
if ! command -v supabase &>/dev/null; then
  error "Supabase CLI not found. Install: npm install -g supabase"
  exit 1
fi

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "main" ]; then
  warn "On branch '$CURRENT_BRANCH', not main. Deploying anyway..."
fi

# Check for service role keys
MISSING_KEYS=()
for env in dev prod; do
  if [ -z "${SERVICE_KEYS[$env]}" ]; then
    MISSING_KEYS+=("DOIT_$(echo "$env" | tr '[:lower:]' '[:upper:]')_SERVICE_ROLE_KEY")
  fi
done

if [ ${#MISSING_KEYS[@]} -gt 0 ]; then
  error "Missing service role keys: ${MISSING_KEYS[*]}"
  echo ""
  echo "  Get them from Supabase Dashboard > Project Settings > API > service_role key"
  echo "  Then set:"
  echo "    export DOIT_DEV_SERVICE_ROLE_KEY=eyJ...   (project: ${PROJECTS[dev]})"
  echo "    export DOIT_PROD_SERVICE_ROLE_KEY=eyJ...  (project: ${PROJECTS[prod]})"
  echo ""
  echo "  Or run with SKIP_MISSING=true to skip projects without keys."
  if [ "${SKIP_MISSING:-}" != "true" ]; then
    exit 1
  fi
fi

# ---- Deploy to each project ----
for env in dev prod; do
  PROJECT_REF="${PROJECTS[$env]}"
  ANON_KEY="${ANON_KEYS[$env]}"
  SERVICE_ROLE_KEY="${SERVICE_KEYS[$env]}"
  SUPABASE_URL="https://${PROJECT_REF}.supabase.co"

  echo ""
  info "========================================"
  info "Deploying to: $env ($PROJECT_REF)"
  info "========================================"
  echo ""

  # Skip if no service role key for this project
  if [ -z "$SERVICE_ROLE_KEY" ]; then
    warn "No service role key for $env — skipping."
    warn "Set DOIT_$(echo "$env" | tr '[:lower:]' '[:upper:]')_SERVICE_ROLE_KEY to deploy."
    continue
  fi

  # Step 1: Link the project
  info "[1/4] Linking Supabase project..."
  if supabase link --project-ref "$PROJECT_REF" 2>&1; then
    info "  Project linked."
  elif [ -n "${SUPABASE_DB_PASSWORD:-}" ]; then
    info "  Trying database password fallback..."
    supabase link --project-ref "$PROJECT_REF" --password "$SUPABASE_DB_PASSWORD" 2>&1 || {
      warn "  Password link also failed. Continuing — deploy step may fail."
    }
  else
    warn "  Link failed. Continuing — deploy step may fail."
    warn "  (supabase login or SUPABASE_DB_PASSWORD env needed)"
  fi

  # Step 2: Set function secrets
  info "[2/4] Setting Edge Function secrets..."
  supabase secrets set \
    SUPABASE_URL="$SUPABASE_URL" \
    SUPABASE_ANON_KEY="$ANON_KEY" \
    SUPABASE_SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY" \
    --project-ref "$PROJECT_REF" 2>&1 || {
    warn "  Secrets set failed. Function deploy may not work if secrets are missing."
  }

  # Step 3: Deploy the function
  info "[3/4] Deploying agent-settings Edge Function..."
  if supabase functions deploy agent-settings --project-ref "$PROJECT_REF" 2>&1; then
    info "  Function deployed successfully."
  else
    error "  Function deploy FAILED."
    error "  Make sure you are logged in: supabase login"
    continue
  fi

  # Step 4: Verify
  info "[4/4] Verifying agent-settings endpoint..."
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$SUPABASE_URL/functions/v1/agent-settings" \
    -H "Content-Type: application/json" \
    -d '{"action":"get"}' 2>/dev/null || echo "000")

  if [ "$HTTP_CODE" = "401" ]; then
    echo -e "  ${GREEN}✅ Function is live (HTTP 401 — JWT verification active)${NC}"
  elif [ "$HTTP_CODE" = "200" ]; then
    echo -e "  ${GREEN}✅ Function is live (HTTP 200)${NC}"
  elif [ "$HTTP_CODE" = "404" ]; then
    echo -e "  ${RED}❌ Function NOT found (HTTP 404) — deploy may have failed${NC}"
  else
    echo -e "  ${YELLOW}⚠️ Unexpected: HTTP $HTTP_CODE${NC}"
  fi
done

# ---- Apply migration ----
echo ""
info "========================================"
info "Applying migration to all projects"
info "========================================"
echo ""

for env in dev prod; do
  PROJECT_REF="${PROJECTS[$env]}"
  SERVICE_ROLE_KEY="${SERVICE_KEYS[$env]}"

  if [ -z "$SERVICE_ROLE_KEY" ]; then
    warn "Skipping migration for $env (no service role key)."
    continue
  fi

  echo ""
  info "Applying migration to $env ($PROJECT_REF)..."
  echo "  Migration: 20240601000043_self_hosted_provider_base_url.sql"
  echo "  Changes: provider column becomes text (not enum), adds base_url column"

  if supabase db push --project-ref "$PROJECT_REF" 2>&1; then
    info "  Migration applied successfully."
  else
    warn "  db push failed. Run this SQL manually in Supabase Dashboard > SQL Editor:"
    echo ""
    echo "  ---- SQL to run ----"
    cat "$PROJECT_DIR/supabase/migrations/20240601000043_self_hosted_provider_base_url.sql"
    echo "  ---- end SQL ----"
  fi
done

# ---- Summary ----
echo ""
info "========================================"
info "Deployment Complete"
info "========================================"
echo ""
echo "  Next steps:"
echo "  1. Build and run the iOS app"
echo "  2. Go to Settings > Model"
echo "  3. The red 404 error should be gone"
echo "  4. Self-managed providers with base_url should save successfully"
echo ""

# Verify production
echo "  Quick production check:"
PROD_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "https://${PROJECTS[prod]}.supabase.co/functions/v1/agent-settings" \
  -H "Content-Type: application/json" \
  -d '{"action":"get"}' 2>/dev/null || echo "000")
if [ "$PROD_CODE" = "401" ] || [ "$PROD_CODE" = "200" ]; then
  echo -e "  Production: ${GREEN}✅ Function live (HTTP $PROD_CODE)${NC}"
else
  echo -e "  Production: ${RED}❌ Function not reachable (HTTP $PROD_CODE)${NC}"
  echo "  Run deploy again, or deploy manually from Supabase Dashboard."
fi
