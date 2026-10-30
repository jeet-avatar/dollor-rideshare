#!/usr/bin/env bash
# =============================================================================
# Dollor.ai Smoke Test Runner
# =============================================================================
# Usage:
#   scripts/smoke-test.sh staging      # Run all tests against staging
#   scripts/smoke-test.sh production   # Run safe tests against production
#   scripts/smoke-test.sh              # Defaults to staging
#
# Exit code: 0 = all pass, 1 = failures
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKEND_DIR="$REPO_ROOT/apps/web/p2p-platform/backend"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
ENV="${1:-staging}"

if [[ "$ENV" != "staging" && "$ENV" != "production" ]]; then
    echo "ERROR: Invalid environment '$ENV'. Use 'staging' or 'production'."
    echo "Usage: $0 [staging|production]"
    exit 1
fi

# ---------------------------------------------------------------------------
# Environment URLs for display
# ---------------------------------------------------------------------------
if [[ "$ENV" == "staging" ]]; then
    TARGET_URL="${STAGING_API_URL:?set STAGING_API_URL to the staging API base URL}"
else
    TARGET_URL="https://api.dollor.ai"
fi

echo "============================================="
echo " Dollor.ai Smoke Tests"
echo "============================================="
echo " Environment: $ENV"
echo " Target URL:  $TARGET_URL"
echo " Time:        $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
echo "============================================="
echo ""

# ---------------------------------------------------------------------------
# Build pytest command
# ---------------------------------------------------------------------------
SMOKE_DIR="$BACKEND_DIR/tests/smoke"

PYTEST_ARGS=(
    -v
    --tb=short
    --no-header
    "--env=$ENV"
    -c /dev/null
    --rootdir="$SMOKE_DIR"
    --confcutdir="$SMOKE_DIR"
    "$SMOKE_DIR/"
)

if [[ "$ENV" == "production" ]]; then
    echo "[INFO] Production mode -- staging_only tests will be auto-skipped."
    echo ""
fi

# ---------------------------------------------------------------------------
# Run tests
# ---------------------------------------------------------------------------

# Activate venv if present
if [[ -f "$BACKEND_DIR/venv/bin/activate" ]]; then
    source "$BACKEND_DIR/venv/bin/activate"
fi

# Run from smoke dir to avoid parent conftest loading
cd "$SMOKE_DIR"

START_TIME=$(date +%s)

set +e
python -m pytest "${PYTEST_ARGS[@]}" 2>&1
EXIT_CODE=$?
set -e

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================="
echo " Smoke Test Summary"
echo "============================================="
echo " Environment: $ENV"
echo " Target URL:  $TARGET_URL"
echo " Duration:    ${DURATION}s"
if [[ $EXIT_CODE -eq 0 ]]; then
    echo " Result:      PASS"
else
    echo " Result:      FAIL (exit code $EXIT_CODE)"
fi
echo "============================================="

exit $EXIT_CODE
