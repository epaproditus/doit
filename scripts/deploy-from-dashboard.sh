#!/usr/bin/env bash
# deploy-from-dashboard.sh
#
# PLY-309: Helper script for manually deploying agent-settings via Dashboard.
#
# This script prints the exact steps to follow in the Supabase Dashboard.
# Use this if you don't have a Supabase PAT with Management API access.
#
# Usage:
#   ./scripts/deploy-from-dashboard.sh
#
# What it does:
#   1. Reads the function source and prints it for copy-paste
#   2. Reads migration SQL files for copy-paste
#   3. Shows the exact Dashboard navigation steps

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PROJECT_REF="nportxmsauhezjdubsma"
SUPABASE_URL="https://${PROJECT_REF}.supabase.co"
ANON_KEY="sb_publishable_Y_ug6gCljcKuPnst_s1TMw_oZ5BosqD"

echo "================================================================"
echo "  PLY-309: Deploy agent-settings Edge Function via Dashboard"
echo "  Production project: $PROJECT_REF"
echo "================================================================"
echo ""
echo "Open: https://supabase.com/dashboard/project/$PROJECT_REF"
echo ""
echo "--- Step 1: Apply Migration #43 (base_url column) ---"
echo "Go to: SQL Editor > New Query"
echo "Paste and run the SQL from:"
echo "  $PROJECT_DIR/supabase/migrations/20240601000043_self_hosted_provider_base_url.sql"
echo ""
echo "--- Step 2: Apply Migration #44 (RLS policies) ---"
echo "In the same SQL Editor, paste and run:"
echo "  $PROJECT_DIR/supabase/migrations/20240601000044_rls_for_user_setting_upsert.sql"
echo ""
echo "--- Step 3: Create/Update Edge Function ---"
echo "Go to: Edge Functions > Create a new function"
echo "  Name: agent-settings"
echo "  Verify JWT: ON (default)"
echo "  Source: Copy the entire file below"
echo ""
echo "=== FUNCTION SOURCE (cat supabase/functions/agent-settings/index.ts) ==="
cat "$PROJECT_DIR/supabase/functions/agent-settings/index.ts"
echo ""
echo "=== END FUNCTION SOURCE ==="
echo ""
echo "--- Step 4: Set Edge Function Secrets ---"
echo "Go to: Project Settings > API > Project Secrets"
echo ""
echo "Add these secrets (click 'Reveal' then 'Add new secret'):"
echo ""
echo "  Name: SUPABASE_URL"
echo "  Value: $SUPABASE_URL"
echo ""
echo "  Name: SUPABASE_ANON_KEY"
echo "  Value: $ANON_KEY"
echo ""
echo "NOTE: SUPABASE_SERVICE_ROLE_KEY is NOT required."
echo "  The function uses user-level auth with RLS policies."
echo ""
echo "--- Step 5: Verify ---"
echo "After saving, verify the function is live:"
echo ""
echo "  curl -s -o /dev/null -w '%{http_code}' -X POST \\"
echo "    $SUPABASE_URL/functions/v1/agent-settings \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"action\":\"get\"}'"
echo ""
echo "Expected: 401 (function exists, JWT verification active)"
echo "If you see 404, the function wasn't created yet."
echo ""
echo "================================================================"
echo "  For a full-auth deploy (from a machine with PAT access):"
echo "  export SUPABASE_PAT=sbp_xxx"
echo "  SUPABASE_PROJECT_REF=$PROJECT_REF ./scripts/deploy-agent-settings-direct.sh"
echo "================================================================"
