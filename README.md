# opencode — Self-Hosted AI Coding Agent

<div align="center">

![Docker](https://img.shields.io/badge/Docker-compose-blue?logo=docker&logoColor=white)
![Node](https://img.shields.io/badge/Node-22-bookworm-green?logo=node.js&logoColor=white)
![opencode](https://img.shields.io/badge/opencode-latest-purple)
![Port](https://img.shields.io/badge/port-127.0.0.1:4096-lightgrey)

</div>

A self-hosted [opencode](https://opencode.ai) coding agent in Docker — TUI + web UI on port 4096, preloaded with the **workflow-state-engine** (16-agent scrum orchestration), **lean-ctx** code intelligence, and a curated skill set. Built for environments behind corporate proxies (Zscaler CA trust baked into the image).

## Table of Contents

- [Features](#features)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
  - [Environment Variables](#environment-variables)
  - [Model Fallback](#model-fallback)
- [Project Structure](#project-structure)
- [Engine & Skills](#engine--skills)
- [Troubleshooting](#troubleshooting)

## Features

- **opencode web + TUI** — browser-based agent access, auth-protected, bound to localhost
- **Workflow-state-engine** — `/opt/engine`: contract-driven multi-agent orchestration (plan → execute → review → ship) with scoring gates
- **lean-ctx MCP** — compressed file reads, semantic search, impact analysis, cross-session knowledge
- **4-layer UI/UX pipeline** — `design-exemplar` (84-brand reference library) → `ui-ux-pro-max` (BM25 design-system generator) → `design-taste-frontend` (art direction) → `impeccable` (UI slop-detector gate), enforced by the `design-orchestrator` agent
- **Diagram engine** — `diagram-design` (45+ branded diagram types)
- **Zscaler-safe builds** — drop your corporate CA in `certs/`, npm/git just work
- **Model fallback** — automatic failover on rate limits, quota errors, and provider outages

## Quick Start

The repo ships a standalone compose example (`docker-compose.example.yaml`). It expects to sit **next to** this repo checkout:

```
parent-dir/
├── docker-compose.example.yaml   # or your stack compose
└── opencode/                     # this repo
```

```bash
# 1. Clone
git clone <repo-url> parent-dir/opencode
cd parent-dir

# 2. Set secrets in a .env next to the compose file
cat > .env <<'ENV'
OPENCODE_API_KEY=your-key
SUMOPOD_API_KEY=your-key
SUMOPOD_BASE_URL=https://ai.sumopod.com/v1
SUMOPOD_BASE_MODEL=sumopod/glm-5.3-flash
SUMOPOD_BASE_MODEL_NAME=glm-5.3-flash
CONTEXT7_API_KEY=your-key
ENV

# 3. (Corporate proxy) add CA cert
cp ~/corporate-ca.crt opencode/certs/

# 4. Build & run — one command per OS (populates the offline pre-install
#    store first, then builds; see "Offline builds" below):
sh setup-linux.sh                                            # Linux
./setup-mac.sh                                               # macOS
powershell -ExecutionPolicy Bypass -File setup-windows.ps1   # Windows
```

**Advanced/manual** (skip the setup scripts):

```bash
docker compose -f docker-compose.example.yaml build opencode
docker compose -f docker-compose.example.yaml up -d opencode
```

Open **http://localhost:4096**.

> Rebuild after every engine/skill change — `engine/` is baked into the image (`COPY`), not bind-mounted. `docker compose restart` is NOT enough; use `up -d`.

## Configuration

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `OPENCODE_API_KEY` | ✅ | — | Primary model provider API key |
| `OPENCODE_AUTH_REQUIRED` | — | `true` | Require auth on the web UI |
| `OPENCODE_CONFIG` | — | `/home/node/.config/opencode/opencode.json` | Config path inside container (mounted read-only) |
| `SUMOPOD_API_KEY` | ✅ | — | Sumopod provider key |
| `SUMOPOD_BASE_URL` | ✅ | — | Provider base URL |
| `SUMOPOD_BASE_MODEL` | ✅ | — | Default model ID |
| `SUMOPOD_BASE_MODEL_NAME` | ✅ | — | Display name of the default model |
| `CONTEXT7_API_KEY` | — | — | Context7 docs-lookup MCP |
| `GRAPHIFY_ROOT` | — | `/home/node/workspace` | Graphify index root (currently disabled, config preserved) |

### Model Fallback

`config/opencode-model-fallback.json` (mounted read-only) controls automatic failover:

```json
{
  "enabled": true,
  "retry_on_errors": [401, 402, 403, 429, 500, 502, 503, 504],
  "retryable_error_patterns": [
    "rate limit", "quota exceeded", "usage limit reached",
    "credit balance too low", "service unavailable", "overloaded"
  ],
  "max_fallback_attempts": 5,
  "cooldown_seconds": 60,
  "timeout_seconds": 60,
  "notify_on_fallback": true,
  "fallback_models": ["sumopod/deepseek-flash"]
}
```

| Field | Meaning |
|-------|---------|
| `retry_on_errors` | HTTP codes that trigger fallback |
| `retryable_error_patterns` | Error-text substrings that trigger fallback |
| `max_fallback_attempts` | Cap per request chain |
| `cooldown_seconds` / `timeout_seconds` | Backoff + per-attempt timeout |
| `notify_on_fallback` | Surface fallback events in the session |
| `fallback_models` | Ordered failover chain |

## Project Structure

```
opencode/
├── Dockerfile                     # node:22-bookworm-slim + CA trust + engine bake
├── entrypoint.sh                  # startup: config, MCP wiring, web server
├── docker-compose.example.yaml    # standalone single-service example
├── certs/                         # corporate CA certs (gitignored except placeholders)
├── config/
│   ├── opencode.json              # main opencode config (models, MCPs, agents)
│   └── opencode-model-fallback.json
├── engine/                        # workflow-state-engine → /opt/engine in image
│   ├── agents/                    # 16 scrum-team agent definitions
│   ├── skills/                    # 64 skills (incl. full UI/UX pipeline: design-exemplar, ui-ux-pro-max, impeccable)
│   └── commands/                  # slash commands
└── session/                       # orchestration state (contract.json, archive/)
```

## Engine & Skills

The engine is baked into the image at `/opt/engine` and symlinked into opencode's config:

- `~/.config/opencode/skills` → `/opt/engine/skills`
- `~/.config/opencode/command` → `/opt/engine/commands`

Add a skill by dropping a directory under `engine/skills/<name>/SKILL.md`, rebuilding, and (for enforcement) attaching it in `engine/agents/<agent>.md` + `engine/agent.md` §3/§7.

### UI/UX pipeline

UI tasks route through `design-orchestrator` (mode: primary), which enforces the mandatory layer order:

| Layer | Skill | Use when |
|-------|-------|----------|
| Exemplar | `design-exemplar` | A reference brand is named ("make it look like Linear") |
| Generator | `ui-ux-pro-max` | Building from your own product description |
| Taste | `design-taste-frontend` | Always — art-direction pass on the output |
| Gate | `impeccable` | Always — no UI task is done without this review |

Trivial tweaks (<10 lines, no new components) may skip layers 1–2, never layer 4.

The uipro CLI bundle also ships companion skills: `banner-design`, `brand`, `design`, `design-system`, `slides`, `ui-styling`.

## Offline builds (pre-install store)

`pre-install/` is a local, gitignored package store that lets
`docker compose up -d --build` stop re-downloading packages. One setup script per OS
populates the store and then builds — run the one for your OS from any working
directory:

```bash
# Linux
sh setup-linux.sh
# macOS
./setup-mac.sh
# Windows (PowerShell)
powershell -ExecutionPolicy Bypass -File setup-windows.ps1
```

- **Populate runs in a throwaway stock `node:22-bookworm-slim` container** —
  the `populate` compose service (profile `tools`) — so the store can be
  filled before the custom image exists, fixing the first-run
  chicken-and-egg problem. The script is idempotent: re-runs fetch only
  what is missing.
- **Builds then install offline-first**: Docker cache mounts plus the
  store's npm tarballs, pip wheels, and lean-ctx binary. Anything absent
  still falls back to the network, so builds never break on a fresh
  checkout.
- **The store is portable**: it lives in the workspace, so copying the
  workspace to another machine carries the store with it. Its contents are
  gitignored (`pre-install/**` except `.gitkeep`) and are never committed
  or pushed.

**Alternative** — once the custom image is already built, you can still
populate from inside the running container (root is only needed for the
apt section):

    docker compose exec -u root opencode sh populate-preinstall.sh

**Store layout** — every artifact type follows the same skip-if-exists pattern:
`populate-preinstall.sh` checks the marker (tarball, wheel, binary, `.deb`,
clone dir, zip) and fetches only what is missing. The `git/` and `dist/`
sections are wired in the script and reserved for future artifacts installed
from a git clone or a direct download — they follow the same
`fetch_if_missing` pattern.

| Directory | Contents |
|-----------|----------|
| `pre-install/npm/` | npm tarballs (`npm pack`) for opencode, MCP servers, and plugins |
| `pre-install/pip/` | pip wheels — full dependency closure of `graphifyy[mcp]`, `mcp<2`, `mcp-server-fetch` |
| `pre-install/bin/` | release binaries (`lean-ctx`) |
| `pre-install/apt/` | `.deb` closure of the base apt packages (populated as root) |
| `pre-install/git/` | shallow git clones (reserved — future git-sourced artifacts) |
| `pre-install/dist/` | zips / tarballs / direct downloads (reserved — future URL-fetched artifacts) |

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `npm install` / `git clone` TLS errors at build | CA cert missing — add to `certs/`, rebuild |
| New skills/commands not appearing | Container runs old image — `docker compose build opencode && docker compose up -d opencode` |
| Changes gone after container recreate | Expected — engine is baked; commit to repo, rebuild |
| Web UI unreachable | Bound to `127.0.0.1:4096` by design; access via SSH tunnel or reverse proxy |
