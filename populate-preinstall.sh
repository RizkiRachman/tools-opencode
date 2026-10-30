#!/bin/sh
# Populate the offline package store (pre-install/) used by the Docker build.
#
# pre-install/ is fully gitignored (except its .gitkeep files): its contents
# live only on the local disk / inside the workspace volume and are NEVER
# committed or pushed. The store is portable - copy the workspace to another
# machine and the store comes with it.
#
# Idempotent: everything already present is skipped, so re-runs fetch only
# what is missing. Root is required only for the apt section.
set -eu

# Versions - must match the Dockerfile ARG defaults (env-overridable).
OPENCODE_VERSION="${OPENCODE_VERSION:-1.19.0}"
CONTEXT7_VERSION="${CONTEXT7_VERSION:-4.4.1}"
GRAPHIFY_VERSION="${GRAPHIFY_VERSION:-0.8.49}"
LEAN_CTX_VERSION="${LEAN_CTX_VERSION:-3.10.2}"
MCP_MEMORY_VERSION="${MCP_MEMORY_VERSION:-2.0.1}"
MCP_EVERYTHING_VERSION="${MCP_EVERYTHING_VERSION:-2.1.0}"
PLUGIN_VERSION=1.19.0         # @opencode-ai/plugin
MODEL_FALLBACK_VERSION=0.3.2  # @razroo/opencode-model-fallback
DCP_VERSION=3.2.0             # @tarquinen/opencode-dcp
WEBSEARCH_VERSION=1.2.0       # opencode-websearch-cited

STORE_DIR=$(cd "$(dirname "$0")" && pwd)/pre-install
mkdir -p "$STORE_DIR/npm" "$STORE_DIR/pip" "$STORE_DIR/bin" "$STORE_DIR/apt"

ADDED=0
SKIPPED=0

mark_added() {
  ADDED=$((ADDED + 1))
  echo "  added:   $1"
}

mark_skipped() {
  SKIPPED=$((SKIPPED + 1))
  echo "  skipped: $1"
}

# True when a tarball for the package (any version) is already in the store.
# npm pack writes scoped packages as '@scope+name-<version>.tgz'.
# $glob is expanded unquoted on purpose (paths in this workspace have no spaces).
npm_tarball_present() {
  pkg=${1%@*}
  case "$pkg" in
    @*/*) glob="$STORE_DIR/npm/${pkg%%/*}+${pkg#*/}-"*.tgz ;;
    *)    glob="$STORE_DIR/npm/$pkg-"*.tgz ;;
  esac
  for f in $glob; do
    if [ -e "$f" ]; then
      return 0
    fi
  done
  return 1
}

npm_maybe_pack() {
  if npm_tarball_present "$1"; then
    mark_skipped "$1 (tarball already in store)"
  else
    npm pack "$1" --pack-destination "$STORE_DIR/npm"
    mark_added "$1"
  fi
}

echo "==> npm tarballs"
npm_maybe_pack "opencode-ai@${OPENCODE_VERSION}"
npm_maybe_pack "@upstash/context7-mcp@${CONTEXT7_VERSION}"
npm_maybe_pack "@modelcontextprotocol/server-memory@${MCP_MEMORY_VERSION}"
npm_maybe_pack "@modelcontextprotocol/server-everything@${MCP_EVERYTHING_VERSION}"
npm_maybe_pack "@opencode-ai/plugin@${PLUGIN_VERSION}"
npm_maybe_pack "@razroo/opencode-model-fallback@${MODEL_FALLBACK_VERSION}"
npm_maybe_pack "@tarquinen/opencode-dcp@${DCP_VERSION}"
npm_maybe_pack "opencode-websearch-cited@${WEBSEARCH_VERSION}"

# True when at least one wheel is already in the store.
pip_wheels_present() {
  for f in "$STORE_DIR"/pip/*.whl; do
    if [ -e "$f" ]; then
      return 0
    fi
  done
  return 1
}

echo "==> python wheels (full closure)"
if pip_wheels_present; then
  mark_skipped "pip wheels (already in store)"
else
  # The container ships pipx but NOT python3-pip; prefer the graphifyy
  # venv's pip and fall back to python3 -m pip (e.g. on a dev host).
  if [ -x /opt/pipx/venvs/graphifyy/bin/pip ]; then
    /opt/pipx/venvs/graphifyy/bin/pip download --dest "$STORE_DIR/pip" \
      "graphifyy[mcp]==${GRAPHIFY_VERSION}" "mcp<2" mcp-server-fetch
  else
    python3 -m pip download --dest "$STORE_DIR/pip" \
      "graphifyy[mcp]==${GRAPHIFY_VERSION}" "mcp<2" mcp-server-fetch
  fi
  mark_added "pip wheels: graphifyy[mcp]==${GRAPHIFY_VERSION}, mcp<2, mcp-server-fetch"
fi

echo "==> lean-ctx binary"
if [ -f "$STORE_DIR/bin/lean-ctx" ]; then
  mark_skipped "lean-ctx ${LEAN_CTX_VERSION} (binary already in store)"
else
  HOME=$(mktemp -d)
  curl -fsSL \
    "https://raw.githubusercontent.com/yvgude/lean-ctx/v${LEAN_CTX_VERSION}/install.sh" \
    -o "$HOME/inst.sh"
  LEAN_CTX_NO_ONBOARD=1 sh "$HOME/inst.sh" --download
  cp "$HOME/.local/bin/lean-ctx" "$STORE_DIR/bin/lean-ctx"
  chmod 0755 "$STORE_DIR/bin/lean-ctx"
  rm -rf "$HOME"
  mark_added "lean-ctx ${LEAN_CTX_VERSION}"
fi

echo "==> apt debs (root only)"
apt_debs_present() {
  for f in "$STORE_DIR"/apt/*.deb; do
    if [ -e "$f" ]; then
      return 0
    fi
  done
  return 1
}

if [ "$(id -u)" -eq 0 ]; then
  if apt_debs_present; then
    mark_skipped "apt debs (already in store)"
  else
    mkdir -p "$STORE_DIR/apt/partial"
    apt-get update
    apt-get install --reinstall --download-only -y --no-install-recommends \
      -o Dir::Cache::archives="$STORE_DIR/apt" \
      git curl jq ripgrep ca-certificates python3 pipx python3-venv coreutils procps
    mark_added "apt debs"
  fi
else
  echo "  apt section skipped - re-run with: docker compose exec -u root opencode sh populate-preinstall.sh"
fi

echo ""
echo "==> done: ${ADDED} added, ${SKIPPED} skipped - store at ${STORE_DIR}"
