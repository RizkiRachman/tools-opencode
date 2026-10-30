#!/bin/sh
# First-run setup for macOS: populate the offline pre-install store, then build & start.
# POSIX sh. Docker Desktop is required. See README.md "Offline builds". Usage: ./setup-mac.sh
set -eu

REPO_ROOT=$(cd "$(dirname "$0")" && pwd)

# 1. Locate the compose file: $COMPOSE_FILE override wins, then a parent-level
#    docker-compose.yaml (workspace layout), else the repo's example. The
#    example's paths (./opencode, ./pre-install) are relative to the parent
#    dir, so point --project-directory there when it is used in place.
if [ -n "${COMPOSE_FILE:-}" ]; then
  compose() { docker compose -f "$COMPOSE_FILE" "$@"; }
  echo "==> compose file: $COMPOSE_FILE (from \$COMPOSE_FILE)"
elif [ -f "$REPO_ROOT/../docker-compose.yaml" ]; then
  compose() { docker compose -f "$REPO_ROOT/../docker-compose.yaml" "$@"; }
  echo "==> compose file: parent docker-compose.yaml"
else
  compose() { docker compose -f "$REPO_ROOT/docker-compose.example.yaml" --project-directory "$REPO_ROOT/.." "$@"; }
  echo "==> compose file: repo docker-compose.example.yaml (project dir: $REPO_ROOT/..)"
fi

# 2. Docker + compose v2 available?
if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker not found. Install Docker Desktop (macOS):" >&2
  echo "  https://www.docker.com/products/docker-desktop/" >&2
  exit 1
fi
if ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: 'docker compose' v2 plugin not available. Update Docker Desktop." >&2
  exit 1
fi

# 3. CRLF guard (best-effort, non-fatal): autocrlf corruption breaks sh scripts.
if grep -q "$(printf '\r')" "$REPO_ROOT/populate-preinstall.sh" 2>/dev/null; then
  echo "WARN: CRLF line endings detected in populate-preinstall.sh."
  echo "      Fix in place with: sed -i '' 's/\r$//' $REPO_ROOT/populate-preinstall.sh"
fi

# 4. Populate the offline store in a throwaway stock node container
#    (works before the custom image exists; re-runs fetch only what is missing).
echo "==> populating pre-install store (compose profile: tools)"
compose --profile tools run --rm populate

# 5. Build & start.
echo "==> building and starting"
compose up -d --build

# 6. Done.
echo ""
echo "==> done. Store: $REPO_ROOT/pre-install (gitignored, never committed or pushed)."
echo "    Re-populate later: re-run this script (fetches only what is missing)."
echo "    Next: open http://localhost:4096 once the build finishes."
