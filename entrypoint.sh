#!/bin/sh

set -eu

# -----------------------------------------------------------------------------
# OpenCode authentication
# -----------------------------------------------------------------------------

OPENCODE_AUTH_REQUIRED="${OPENCODE_AUTH_REQUIRED:-true}"
OPENCODE_AUTH_DIR="${OPENCODE_AUTH_DIR:-$HOME/.local/share/opencode}"
OPENCODE_AUTH_FILE="${OPENCODE_AUTH_FILE:-$OPENCODE_AUTH_DIR/auth.json}"

configure_opencode_auth() {
  if [ -z "${OPENCODE_API_KEY:-}" ]; then
    if [ "$OPENCODE_AUTH_REQUIRED" = "true" ]; then
      echo "[entrypoint] ERROR: OPENCODE_API_KEY is required" >&2
      exit 1
    fi

    echo "[entrypoint] OPENCODE_API_KEY is not set; skipping authentication"
    return
  fi

  if ! command -v node >/dev/null 2>&1; then
    echo "[entrypoint] ERROR: node executable not found" >&2
    exit 1
  fi

  mkdir -p "$OPENCODE_AUTH_DIR"
  chmod 700 "$OPENCODE_AUTH_DIR"

  export OPENCODE_AUTH_FILE

  node <<'NODE'
const fs = require("fs");
const path = require("path");

const authFile = process.env.OPENCODE_AUTH_FILE;
const apiKey = process.env.OPENCODE_API_KEY;

if (!authFile) {
  console.error("[entrypoint] ERROR: OPENCODE_AUTH_FILE is missing");
  process.exit(1);
}

if (!apiKey) {
  console.error("[entrypoint] ERROR: OPENCODE_API_KEY is missing");
  process.exit(1);
}

let auth = {};

if (fs.existsSync(authFile)) {
  try {
    const content = fs.readFileSync(authFile, "utf8").trim();

    if (content) {
      auth = JSON.parse(content);
    }
  } catch (error) {
    console.error(
      `[entrypoint] ERROR: cannot parse ${authFile}: ${error.message}`
    );
    process.exit(1);
  }
}

if (
  auth.opencode &&
  auth.opencode.type === "api" &&
  auth.opencode.key === apiKey
) {
  console.log("[entrypoint] OpenCode authentication already configured");
  process.exit(0);
}

auth.opencode = {
  type: "api",
  key: apiKey
};

fs.mkdirSync(path.dirname(authFile), {
  recursive: true,
  mode: 0o700
});

const temporaryFile = `${authFile}.tmp`;

fs.writeFileSync(
  temporaryFile,
  `${JSON.stringify(auth, null, 2)}\n`,
  {
    encoding: "utf8",
    mode: 0o600
  }
);

fs.renameSync(temporaryFile, authFile);
fs.chmodSync(authFile, 0o600);

console.log("[entrypoint] OpenCode authentication configured");
NODE
}

configure_opencode_auth

# OpenCode reads the credential from auth.json.
# Remove the original token from the environment inherited by plugins and MCPs.
unset OPENCODE_API_KEY

# -----------------------------------------------------------------------------
# Graphify initialization
# -----------------------------------------------------------------------------

GRAPHIFY_ROOT="${GRAPHIFY_ROOT:-/home/node/workspace}"
GRAPHIFY_GRAPH="${GRAPHIFY_GRAPH:-$GRAPHIFY_ROOT/graphify-out/graph.json}"
GRAPHIFY_BUILD="${GRAPHIFY_BUILD:-if-missing}"
GRAPHIFY_TIMEOUT="${GRAPHIFY_TIMEOUT:-900}"

case "$GRAPHIFY_BUILD" in
  always)
    build=1
    ;;
  never)
    build=0
    ;;
  if-missing)
    if [ -f "$GRAPHIFY_GRAPH" ]; then
      build=0
    else
      build=1
    fi
    ;;
  *)
    echo "[entrypoint] ERROR: invalid GRAPHIFY_BUILD=$GRAPHIFY_BUILD" >&2
    echo "[entrypoint] Valid values: if-missing, always, never" >&2
    exit 1
    ;;
esac

if [ "$build" = "1" ]; then
  if [ ! -d "$GRAPHIFY_ROOT" ]; then
    echo "[entrypoint] WARNING: GRAPHIFY_ROOT not found: $GRAPHIFY_ROOT" >&2
    echo "[entrypoint] continuing without building Graphify" >&2
  elif ! command -v graphify >/dev/null 2>&1; then
    echo "[entrypoint] WARNING: graphify executable not found" >&2
    echo "[entrypoint] continuing without building Graphify" >&2
  else
    echo "[entrypoint] building Graphify graph"
    echo "[entrypoint] root=$GRAPHIFY_ROOT"
    echo "[entrypoint] graph=$GRAPHIFY_GRAPH"
    echo "[entrypoint] timeout=${GRAPHIFY_TIMEOUT}s"

    if (
      cd "$GRAPHIFY_ROOT" &&
      timeout "$GRAPHIFY_TIMEOUT" nice -n 10 graphify update .
    ); then
      if [ -f "$GRAPHIFY_GRAPH" ]; then
        echo "[entrypoint] Graphify graph ready: $GRAPHIFY_GRAPH"
      else
        echo "[entrypoint] WARNING: Graphify completed without creating:" >&2
        echo "[entrypoint] $GRAPHIFY_GRAPH" >&2
      fi
    else
      status=$?

      if [ "$status" = "124" ]; then
        echo "[entrypoint] WARNING: Graphify timed out after ${GRAPHIFY_TIMEOUT}s" >&2
      else
        echo "[entrypoint] WARNING: Graphify failed with status $status" >&2
      fi

      echo "[entrypoint] continuing without a Graphify graph" >&2
    fi
  fi
else
  echo "[entrypoint] Graphify graph present or build disabled; skipping build"
fi

# -----------------------------------------------------------------------------
# MCP readiness checks
# -----------------------------------------------------------------------------
#
# OpenCode launches every `local` MCP server from opencode.json as a stdio
# process. Before starting OpenCode, probe each enabled server with a JSON-RPC
# `initialize` handshake so a dead MCP is detected at boot instead of
# mid-session.
#
# Env:
#   MCP_CHECK_ENABLED  true|false  enable the preflight (default: true)
#   MCP_CHECK_TIMEOUT  seconds     per-server timeout (default: 20)
#   MCP_CHECK_STRICT   true|false  exit 1 if any server is not ready (default: false)

MCP_CHECK_ENABLED="${MCP_CHECK_ENABLED:-true}"
MCP_CHECK_TIMEOUT="${MCP_CHECK_TIMEOUT:-20}"
MCP_CHECK_STRICT="${MCP_CHECK_STRICT:-false}"
MCP_CHECK_CONFIG="${OPENCODE_CONFIG:-$HOME/.config/opencode/opencode.json}"

mcp_check_servers() {
  if [ "$MCP_CHECK_ENABLED" != "true" ]; then
    echo "[entrypoint] MCP readiness checks disabled"
    return 0
  fi

  if ! command -v jq >/dev/null 2>&1; then
    echo "[entrypoint] WARNING: jq not found; skipping MCP readiness checks" >&2
    return 0
  fi

  if [ ! -f "$MCP_CHECK_CONFIG" ]; then
    echo "[entrypoint] WARNING: config not found ($MCP_CHECK_CONFIG); skipping MCP readiness checks" >&2
    return 0
  fi

  init='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"opencode-preflight","version":"1.0"}}}'

  names=$(jq -r '.mcp // {} | to_entries[] | select(.value.type == "local") | select(.value.enabled != false) | .key' "$MCP_CHECK_CONFIG" 2>/dev/null || true)

  if [ -z "$names" ]; then
    echo "[entrypoint] no enabled local MCP servers to check"
    return 0
  fi

  echo "[entrypoint] checking MCP servers (timeout ${MCP_CHECK_TIMEOUT}s)..."

  failures=0
  total=0

  for name in $names; do
    total=$((total + 1))

    cmd=$(jq -r --arg n "$name" '.mcp[$n].command | @sh' "$MCP_CHECK_CONFIG")

    if ! eval "set -- $cmd"; then
      echo "[entrypoint]   FAIL  $name — malformed command in config" >&2
      failures=$((failures + 1))
      continue
    fi

    bin="$1"

    if ! command -v "$bin" >/dev/null 2>&1; then
      echo "[entrypoint]   FAIL  $name — executable '$bin' not found" >&2
      failures=$((failures + 1))
      continue
    fi

    response=$(printf '%s\n' "$init" | timeout -k 5 "$MCP_CHECK_TIMEOUT" "$@" 2>/dev/null || true)

    if printf '%s' "$response" | grep -q '"result"'; then
      echo "[entrypoint]   OK    $name — connected"
    else
      echo "[entrypoint]   FAIL  $name — no initialize response within ${MCP_CHECK_TIMEOUT}s" >&2
      failures=$((failures + 1))
    fi
  done

  if [ "$failures" -gt 0 ]; then
    echo "[entrypoint] MCP readiness: $((total - failures))/$total ready" >&2
    if [ "$MCP_CHECK_STRICT" = "true" ]; then
      echo "[entrypoint] ERROR: $failures MCP server(s) not ready (MCP_CHECK_STRICT=true)" >&2
      exit 1
    fi
    echo "[entrypoint] WARNING: continuing with $failures MCP server(s) unavailable" >&2
  else
    echo "[entrypoint] MCP readiness: $total/$total ready"
  fi
}

mcp_check_servers

# -----------------------------------------------------------------------------
# Start OpenCode
# -----------------------------------------------------------------------------

echo "[entrypoint] starting: $*"

exec "$@"