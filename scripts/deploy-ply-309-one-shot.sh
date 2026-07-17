#!/usr/bin/env bash
# PLY-309: One-shot deploy of agent-settings Edge Function
# Drops all files to both dev and prod projects.
#
# Usage:
#   export SUPABASE_PAT=sbp_your_new_pat_here
#   ./scripts/deploy-ply-309-one-shot.sh
#
# What it does:
#   1. Applies migration #43 (base_url column, provider→text) to both projects
#   2. Applies migration #44 (RLS policies for user upsert) to both projects
#   3. Deploys agent-settings function to both projects
#   4. Sets function secrets on both projects
#   5. Verifies function responds correctly on both

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Config ──────────────────────────────────────────────────────────────
declare -A PROJECTS
PROJECTS[qjeutitqgdsasccxfxdy]="DEV"
PROJECTS[nportxmsauhezjdubsma]="PROD"

declare -A ANON_KEYS
ANON_KEYS[qjeutitqgdsasccxfxdy]="sb_publishable__PwyGaVjSxKhMKb2HgE3EQ_Id9qCEGJ"
ANON_KEYS[nportxmsauhezjdubsma]="sb_publishable_Y_ug6gCljcKuPnst_s1TMw_oZ5BosqD"

# ── Preflight ───────────────────────────────────────────────────────────
if [ -z "${SUPABASE_PAT:-}" ]; then
  echo "ERROR: SUPABASE_PAT is not set."
  echo "  Get one from: https://supabase.com/dashboard/account/tokens"
  echo "  Then run: SUPABASE_PAT=sbp_xxx ./scripts/deploy-ply-309-one-shot.sh"
  exit 1
fi

echo "=== PLY-309: One-shot deploy ==="
echo "  PAT: ${SUPABASE_PAT:0:12}..."
echo ""

# Verify PAT works
echo ">> Verifying PAT..."
if ! curl -sf -H "Authorization: Bearer $SUPABASE_PAT" \
  "https://api.supabase.com/v1/projects" >/dev/null 2>&1; then
  echo "ERROR: PAT does not have Management API access (401)."
  echo "  Create a new PAT at https://supabase.com/dashboard/account/tokens"
  echo "  Make sure it belongs to the org that owns these projects."
  exit 1
fi
echo "   PAT is valid."
echo ""

# ── Deploy to each project ─────────────────────────────────────────────
for PROJECT_REF in "${!PROJECTS[@]}"; do
  LABEL="${PROJECTS[$PROJECT_REF]}"
  ANON_KEY="${ANON_KEYS[$PROJECT_REF]}"
  SUPABASE_URL="https://${PROJECT_REF}.supabase.co"

  echo "═══════════════════════════════════════════════════════════════"
  echo "  $LABEL Project: $PROJECT_REF"
  echo "═══════════════════════════════════════════════════════════════"

  cd "$PROJECT_DIR"

  # Step 1: Link project
  echo ">> Linking..."
  if supabase link --project-ref "$PROJECT_REF" 2>/dev/null; then
    echo "   Linked via PAT."
  else
    echo "   WARN: Could not link (supabase CLI issue). Continuing with direct API..."
  fi

  # Step 2: Apply migrations
  echo ">> Applying migrations..."
  supabase db push --project-ref "$PROJECT_REF" 2>/dev/null && \
    echo "   Migrations applied." || \
    echo "   WARN: db push failed. Apply manually via Dashboard SQL Editor."

  # Step 3: Deploy function
  echo ">> Deploying agent-settings..."
  supabase functions deploy agent-settings --project-ref "$PROJECT_REF" 2>/dev/null && \
    echo "   ✅ agent-settings deployed." || {
    echo "   CLI deploy failed, trying Management API directly..."
    # Fallback: deploy via Management API curl
    RESP=$(
      curl -sf -X POST \
        "https://api.supabase.com/v1/projects/$PROJECT_REF/functions" \
        -H "Authorization: Bearer $SUPABASE_PAT" \
        -H "Content-Type: application/json" \
        -d "$(cat <<ENDJSON
{
  "slug": "agent-settings",
  "name": "agent-settings",
  "verify_jwt": true,
  "source": $(cat "$PROJECT_DIR/supabase/functions/agent-settings/index.ts" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
}
ENDJSON
)" 2>&1
    )
    if echo "$RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id',''))" 2>/dev/null | grep -q "^[a-z0-9]"; then
      echo "   ✅ agent-settings deployed via API."
    else
      echo "   ❌ Deploy failed. Response: $RESP"
      echo "   Deploy manually via: https://supabase.com/dashboard/project/$PROJECT_REF/edge-functions"
    fi
  }

  # Step 4: Set function secrets (via API)
  echo ">> Setting secrets..."
  curl -sf -X POST \
    "https://api.supabase.com/v1/projects/$PROJECT_REF/secrets" \
    -H "Authorization: Bearer $SUPABASE_PAT" \
    -H "Content-Type: application/json" \
    -d "[
      {\"name\": \"SUPABASE_URL\", \"value\": \"$SUPABASE_URL\"},
      {\"name\": \"SUPABASE_ANON_KEY\", \"value\": \"$ANON_KEY\"}
    ]" >/dev/null 2>&1 && echo "   Secrets set." || echo "   WARN: Secret setting failed."

  # Step 5: Verify
  echo ">> Verifying..."
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    "$SUPABASE_URL/functions/v1/agent-settings" \
    -H "Content-Type: application/json" \
    -d '{"action":"get"}')
  if [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "200" ]; then
    echo "   ✅ $LABEL function is LIVE (HTTP $HTTP_CODE)"
  else
    echo "   ⚠️  $LABEL returned HTTP $HTTP_CODE (expected 401 or 200)"
  fi

  # Step 6: Test self-managed UPDATE
  echo ">> Testing self-managed UPDATE..."
  JWT=$(
    curl -sf -X POST "$SUPABASE_URL/auth/v1/signup" \
      -H "Content-Type: application/json" \
      -H "apikey: $ANON_KEY" \
      -d '{}' | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null
  )
  if [ -n "$JWT" ]; then
    RESULT=$(
      curl -sf -X POST "$SUPABASE_URL/functions/v1/agent-settings" \
        -H "Content-Type: application/json" \
        -H "apikey: $ANON_KEY" \
        -H "Authorization: Bearer $JWT" \
        -d '{"action":"update","provider":"opencode-go","model":"deepseek-v4-flash","base_url":"https://api.example.com/v1"}'
    )
    if echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('setting',{}).get('base_url',''))" 2>/dev/null | grep -q "https://"; then
      echo "   ✅ $LABEL self-managed UPDATE works (base_url persisted)"
    else
      echo "   ⚠️  $LABEL self-managed UPDATE test failed: $RESULT"
    fi
  fi

  echo ""
done

echo "═══════════════════════════════════════════════════════════════"
echo "  Done!"
echo ""
echo "  Next steps:"
echo "  1. Rebuild iOS app and test model settings"
echo "  2. Update GH secret: gh secret set SUPABASE_ACCESS_TOKEN -b \"$SUPABASE_PAT\" -R epaproditus/doit"
echo "═══════════════════════════════════════════════════════════════"
