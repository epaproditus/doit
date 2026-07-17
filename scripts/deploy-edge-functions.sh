#!/usr/bin/env bash
# deploy-edge-functions.sh
#
# Deploy Supabase Edge Functions and apply pending database migrations
# to the linked Supabase project.
#
# Prerequisites:
#   - Supabase CLI installed (npm install -g supabase)
#   - SUPABASE_ACCESS_TOKEN set (PAT with project access)
#   - OR: logged in via `supabase login`
#
# Usage:
#   # Deploy all functions (auto-detect project ref from env files)
#   ./scripts/deploy-edge-functions.sh
#
#   # Deploy a specific function
#   ./scripts/deploy-edge-functions.sh agent-settings
#
#   # Deploy + apply pending migrations
#   FORCE_MIGRATE=true ./scripts/deploy-edge-functions.sh
#
#   # Force a specific project ref
#   SUPABASE_PROJECT_REF=nportxmsauhezjdubsma ./scripts/deploy-edge-functions.sh agent-settings
#
# What this does:
#   1. Detects the Supabase project ref from env, args, or defaults
#   2. Links to the project (authenticated via SUPABASE_ACCESS_TOKEN or login)
#   3. Optionally applies pending DB migrations (set FORCE_MIGRATE=true)
#   4. Deploys specified (or all) Edge Functions
#   5. Verifies agent-settings function responds

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ---- Pre-requisites ----
if ! command -v supabase &>/dev/null; then
  error "supabase CLI not found. Install with: npm install -g supabase"
  exit 1
fi

# ---- Determine project ref ----
# Priority: SUPABASE_PROJECT_REF env > systemd env > local env > default
PROJECT_REF="${SUPABASE_PROJECT_REF:-}"

load_env_ref() {
  local env_file="$1"
  if [ -f "$env_file" ]; then
    local url
    url=$(grep -E '^SUPABASE_URL=' "$env_file" | head -1 | cut -d= -f2-)
    if [ -n "$url" ]; then
      echo "$url" | sed -E 's|https://([^.]+).supabase.co|\1|'
    fi
  fi
}

if [ -z "$PROJECT_REF" ]; then
  PROJECT_REF=$(load_env_ref /etc/doit/connector.env)
fi
if [ -z "$PROJECT_REF" ]; then
  PROJECT_REF=$(load_env_ref "$PROJECT_DIR/runner/connector.env")
fi
if [ -z "$PROJECT_REF" ]; then
  # Last resort: check all known projects
  for env_file in "$PROJECT_DIR"/.env "$PROJECT_DIR/.env.local"; do
    PROJECT_REF=$(load_env_ref "$env_file") && break || true
  done
fi
if [ -z "$PROJECT_REF" ]; then
  error "Could not determine project ref. Set SUPABASE_PROJECT_REF env var."
  exit 1
fi

SUPABASE_URL="https://${PROJECT_REF}.supabase.co"
info "Project ref: $PROJECT_REF"
info "Supabase URL: $SUPABASE_URL"

cd "$PROJECT_DIR"

# ---- Link project (if not already linked) ----
if [ ! -f supabase/.temp/linked-project-ref ] || [ "$(cat supabase/.temp/linked-project-ref 2>/dev/null)" != "$PROJECT_REF" ]; then
  info "Linking Supabase project..."
  supabase link --project-ref "$PROJECT_REF" 2>&1 || warn "Link failed (token may not have access or already linked)"
else
  info "Project already linked."
fi

# ---- Apply pending migrations ----
MIGRATIONS_DIR="supabase/migrations"
if [ "${FORCE_MIGRATE:-}" = "true" ]; then
  info "FORCE_MIGRATE=true — applying pending database migrations..."
  echo "  Migration to apply: $(ls -1 "$MIGRATIONS_DIR"/*.sql 2>/dev/null | sort | tail -1)"
  echo "  This migration changes the provider column from enum to text"
  echo "  and adds the base_url column for self-managed model support."
  echo ""
  if supabase db push --project-ref "$PROJECT_REF" 2>&1; then
    info "Migrations applied successfully."
  else
    warn "db push failed. This requires a SUPABASE_ACCESS_TOKEN with project access."
    warn ""
    warn "To apply manually, run the SQL below in Supabase Dashboard > SQL Editor:"
    warn "---"
    cat "$MIGRATIONS_DIR/20240601000043_self_hosted_provider_base_url.sql" 2>/dev/null || true
    warn "---"
  fi
else
  info "Skipping migrations (set FORCE_MIGRATE=true to apply)."
  info "Latest migration: $(ls -1 "$MIGRATIONS_DIR"/*.sql 2>/dev/null | sort | tail -1 || echo 'none')"
fi
echo ""

# ---- Deploy functions ----
FUNCTIONS=("$@")
if [ ${#FUNCTIONS[@]} -eq 0 ]; then
  # Deploy all functions
  for fn_dir in supabase/functions/*/; do
    fn_name=$(basename "$fn_dir")
    FUNCTIONS+=("$fn_name")
  done
fi

for fn in "${FUNCTIONS[@]}"; do
  info "Deploying function: $fn"
  if supabase functions deploy "$fn" --project-ref "$PROJECT_REF" 2>&1; then
    info "Deployed: $fn"
  else
    error "Failed to deploy $fn"
  fi
done
echo ""

# ---- Verify agent-settings ----
if [[ " ${FUNCTIONS[*]} " =~ "agent-settings" ]] || [ ${#FUNCTIONS[@]} -eq 0 ]; then
  info "Verifying agent-settings function..."
  ANON_KEY="${SUPABASE_ANON_KEY:-}"
  if [ -z "$ANON_KEY" ]; then
    ANON_KEY=$(grep -E '^SUPABASE_ANON_KEY=' "$PROJECT_DIR/runner/connector.env" 2>/dev/null | head -1 | cut -d= -f2-)
  fi

  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$SUPABASE_URL/functions/v1/agent-settings" \
    -H "Content-Type: application/json" \
    -d '{"action":"get"}' 2>/dev/null || echo "000")

  if [ "$HTTP_CODE" = "401" ]; then
    echo "  ✅ Function is live (HTTP 401 — JWT verification active, expected)"
  elif [ "$HTTP_CODE" = "200" ]; then
    echo "  ✅ Function is live (HTTP 200)"
  elif [ "$HTTP_CODE" = "404" ]; then
    echo "  ❌ Function NOT found (HTTP 404) — deployment may have failed"
  fi
fi

echo ""
info "=== Deployment complete ==="
echo ""

if [ "${FORCE_MIGRATE:-}" != "true" ]; then
  echo "  Reminder: Apply pending migration for self-hosted base_url support:"
  echo "    FORCE_MIGRATE=true SUPABASE_PROJECT_REF=$PROJECT_REF $0"
  echo ""
fi

echo "  Next steps (on iOS device/simulator):"
echo "  1. Open Settings > Model"
echo "  2. Confirm no red error banner"
echo "  3. In self-managed BYO mode, provider/model/base_url fields should load"
echo "  4. Save should persist. Then verify in a new session."
