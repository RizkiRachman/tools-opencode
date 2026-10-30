<!-- omit from toc -->
# Workflow State Engine

[![Contributors][contributors-shield]][contributors-url]
[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]
[![MIT License][license-shield]][license-url]
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=for-the-badge)](http://makeapullrequest.com)

<!-- omit from toc -->
### Contract-driven state machine orchestration engine for AI agent workflows

State machine: `INIT → PLAN → PLAN_SCORED → EXECUTE → EXECUTE_SCORED → REVIEW → REVIEW_SCORED → COMPLETE`

Single source of truth for all AI agents. The canonical agent instruction file is [`agent.md`](agent.md) which serves as `instructions[0]` for every agent.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Table of Contents

1. [About The Project](#about-the-project)
   - [Built With](#built-with)
2. [Getting Started](#getting-started)
   - [Prerequisites](#prerequisites)
   - [Build](#build)
   - [Configure](#configure)
   - [Run](#run)
   - [Verify](#verify)
3. [Usage](#usage)
4. [Architecture](#architecture)
5. [State Machine](#state-machine)
6. [Scoring Pipeline](#scoring-pipeline)
7. [Roadmap](#roadmap)
8. [Contributing](#contributing)
9. [License](#license)
10. [Contact](#contact)
11. [Acknowledgments](#acknowledgments)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## About The Project

This is a reusable orchestration toolkit for AI coding agents. It codifies agent collaboration into a gated state machine (8 forward-flow states + BLOCKED escalation), ensuring:

- **Every output is scored** via a three-tier pipeline (rule checks → LLM-as-judge → combined verdict)
- **Every decision is tracked** in the shared JSON envelope (`session/contract.json`)
- **Every session learns** from the last — lessons and patterns persist cross-session via `lean-ctx ctx_knowledge`
- **Every delegation is gated** — agents only transition if scoring thresholds are met


### Built With

This project is a documentation and configuration toolkit for AI agents. It leverages:

[![OpenCode](https://img.shields.io/badge/OpenCode-000000?style=for-the-badge&logo=openai&logoColor=white)](https://github.com/opencode-ai/opencode)
[![LeanCtx](https://img.shields.io/badge/lean--ctx-8B5CF6?style=for-the-badge&logo=github&logoColor=white)](https://github.com/opencode-ai/lean-ctx)
[![Graphify](https://img.shields.io/badge/Graphify-F59E0B?style=for-the-badge&logo=neo4j&logoColor=white)](https://github.com/safishamsi/graphify)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Getting Started

The engine ships **inside the container image**: the Dockerfile copies `engine/` to `/opt/engine/` and symlinks it into OpenCode's config directory (`~/.config/opencode/{agent.md,agents,skills,rules,contract,usage,doc}` → `/opt/engine/*`).

### Prerequisites

- **Docker** — to build and run the image
- **OpenCode** — installed in the image (baked at build time)
- **lean-ctx** — compressed file reads, shell, knowledge persistence, session management — installed in the image

### Build

The Dockerfile bundles OpenCode, lean-ctx, Graphify, and Context7, then copies the engine:

```sh
docker build -t workflow-state-engine .
```

`engine/` changes take effect on **rebuild**.

### Configure

Configuration is **not baked into the image** — it is bind-mounted read-only from `config/`:

```sh
cp config/opencode.proposed.json config/opencode.json
# Edit config/opencode.json — replace API-key placeholders and adjust models/tiers
```

Mount it at `~/.config/opencode/opencode.json` when running. Config changes take effect on **restart**.

### Run

```sh
docker run --rm -it \
  -e OPENCODE_API_KEY="<your-key>" \
  -v "$PWD/config/opencode.json":/home/node/.config/opencode/opencode.json:ro \
  -p 4096:4096 \
  workflow-state-engine
```

The entrypoint configures auth, optionally builds the Graphify index, runs an MCP readiness preflight, then starts OpenCode (`opencode web --hostname 0.0.0.0 --port 4096`).

### Verify

```sh
# Toolkit integrity (symlinks, contract integrity, agent consistency, cross-references)
bash /opt/engine/scripts/validate-toolkit.sh

# Verify MCP servers
bash /opt/engine/scripts/check-mcp.sh

# Load orchestration envelope
lean-ctx ctx_knowledge recall --key "orchestration-contract" --mode exact
```

### Session Setup

The engine runs with a single `session/` directory — no branches required. Initialize or refresh session state with:
> **LOCAL-ONLY:** `session/`, `.session/` and everything inside them are runtime state — NEVER `git add`, commit, or push them (gitignored; history grows unbounded). Archive historical state logs to `.session/` instead.


```sh
bash /opt/engine/scripts/snapshot-contract.sh          # Seed/refresh session/contract.json + state.md
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Usage

### Orchestration Flow

Every task follows this sequence:

| Phase | Agent | Gate |
|-------|-------|------|
| **Refine** | @product-manager | Intent → GWT acceptance criteria, scope + non-goals |
| **Discuss** | Orchestrator (5-lens check) | Requirements clarified |
| **Plan** | @system-analyst (+ @software-architect review) | Impact analysis + plan produced |
| **Spec** (gate) | @system-analyst | GWT-format specs, DDD review |
| **Execute** | @developer (+ @devops-engineer, @fixer) | Implementation + tests |
| **Review** | @quality-analyst + @security-engineer (cross-model) | Code quality, security, DevOps |
| **Process** | @scrum-master | Transitions legal, DoD met, unblock BLOCKED |
| **Verify** | Quality gates | Validated JSON, conventions check |
| **Ship** | Orchestrator (+ @learner) | Post-flight protocol, lessons captured |

### Key Commands

```sh
# Load/save session state
lean-ctx ctx_session save
lean-ctx ctx_session load

# Persist decisions
lean-ctx ctx_knowledge remember key <key> value <value>

# Check blast radius before editing
ctx_impact({target: "symbolName", direction: "upstream"})

# Run the frugality ladder on any code decision
# (See agent.md §5 for the full 6-rung decision ladder)
```


Before writing **any** code, run the frugality ladder:

```
1. Does this need to exist?       → skip it (YAGNI)
2. Standard library does it?      → use it
3. Native platform feature?       → use it
4. Already-installed dependency?  → use it
5. Can this be one line?          → one line
6. Only then: minimum code that works
```


<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Architecture

The engine source lives under `engine/` and is copied to `/opt/engine/` at container build. Edit here, then rebuild to deploy.

```
engine/
├── agent.md           ← Orchestrator instructions (instructions[0])
├── AGENTS.md          ← lean-ctx code intelligence (loaded at session start)
├── agents/            ← 16 agent instruction files
├── skills/            ← 64 skill directories
├── contract/          ← Contract templates & schema (contract.template.json, contract.schema.json, state.template.md)
├── rules/             ← State machine transitions, scoring, cross-model review
├── usage/             ← Tool usage guides (lean-ctx, graphify, context7, opencode)
├── doc/               ← Workflow docs, project docs, cross-agent conventions
├── scripts/           ← Automation & validation scripts
│   ├── snapshot-contract.sh      — Envelope snapshot & archival
│   ├── validate-contract.sh      — Contract JSON validation
│   ├── validate-toolkit.sh       — Full toolkit integrity check
│   ├── auto-score.sh             — Automated 3-tier scoring
│   ├── persist-contract.sh       — Atomic envelope persistence
│   ├── check-conventions.sh      — Architecture convention checking
│   └── health-check.sh           — 6-dimension health verification
├── opencode.json.template ← Redacted config template with annotated MCP tiers
└── setup.sh           ← Bootstrap (standalone clone install)
```

### Agent Delegation Model

```
Orchestrator (orchestrator)
  ├── @product-manager  → Requirements & acceptance criteria (read-only, reviewer model)
  ├── @system-analyst   → Planning & impact analysis (read-only)
  ├── @software-architect → Architecture review (read-only, reviewer model)
  ├── @developer        → Implementation & tests (read/write)
  ├── @devops-engineer  → CI/CD, deploy, observability (read/write)
  ├── @fixer            → Bounded fixes (read/write)
  ├── @quality-analyst  → 5-axis code review (read-only, reviewer model)
  ├── @security-engineer → Security review (read-only, reviewer model)
  ├── @scrum-master     → Process/contract enforcement, unblock (read-only, reviewer model)
  ├── @explorer / @librarian / @observer → Research & exploration (read-only)
  ├── @council          → Multi-model consensus & arbitration (read-only)
  └── @learner          → Post-execution learning
```

**Cross-model review**: executors run on the executor model (`opencode/big-pickle`); reviewers (@product-manager, @software-architect, @quality-analyst, @security-engineer, @scrum-master) run on an independent reviewer model (`sumopod/deepseek-flash`). Conflicting verdicts → `BLOCKED`, arbitrated by @council.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## State Machine

```
INIT → PLAN → PLAN_SCORED → EXECUTE → EXECUTE_SCORED → REVIEW → REVIEW_SCORED → COMPLETE
                              ↘                      ↘                ↘
                          BLOCKED (score < 50 or retry ≥ 3)
                                ↘
                          User intervention → retry with guidance
```

| Transition | Gate | Condition |
|-----------|------|-----------|
| INIT → PLAN | Session created | Always |
| PLAN → PLAN_SCORED | Plan produced | Always |
| EXECUTE → EXECUTE_SCORED | Implementation done | Always |
| EXECUTE_SCORED → REVIEW | Code review | Score ≥ 70 |
| REVIEW → REVIEW_SCORED | Review done | Always |
| REVIEW_SCORED → COMPLETE | All gates pass | Score ≥ 70 |
| Any → BLOCKED | Escalation | Score < 50 or retry ≥ 3 |

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Scoring Pipeline

Three-tier scoring runs after every delegation:

| Tier | Method | Deduction / Range |
|------|--------|-------------------|
| 1 | Rule-based checks (start 100) | Schema -15, permissions -40, blast radius -40, writing order -15, over-engineering -15 |
| 2 | LLM-as-judge | Requirements 0-40, governance 0-30, completeness 0-20, edge cases 0-10 |
| 3 | **Combined verdict** | **≥ 70 PASS** · 50–69 RETRY (max 3) · < 50 BLOCKED |

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Roadmap

- [x] Core state machine (8 forward-flow states + BLOCKED)
- [x] Three-tier scoring pipeline
- [x] 15 specialized agent instructions (scrum team)
- [x] Vercel-style skill packaging (package.json per skill)
- [x] Cross-reference audit and broken-link detection
- [x] Template configuration (opencode.json.template with MCP/plugin tiers)
- [x] MCP and plugin verification scripts (scripts/check-mcp.sh, check-plugins.sh)
- [x] Architecture convention checking (scripts/check-conventions.sh — agent paths, JSON schema, forbidden patterns, state.md sync)
- [x] Toolkit integrity validation (scripts/validate-toolkit.sh — symlinks, contract integrity, agent consistency, cross-references)
- [x] Session archival (scripts/archive-sessions.sh — days-based cleanup with dry-run/restore)
- [x] JSON Schema enforcement (contract/contract.schema.json — Draft 2020-12, $defs, numeric constraints, valid states)
- [x] CI/CD governance pipeline (.github/workflows/governance.yml — conventions, schema, toolkit validation)
- [x] Token budget enforcement (token_budget in contract.json + TOKEN_001-004 in rules.json)
- [x] Configuration template sync (opencode.json.template — 4 placeholders, synced from opencode.json)
- [x] Session archival protocol (session/ directory — per-session snapshots, append-only state log)
- [ ] Skill registry publishing (skills.sh)
- [x] Multi-model council consensus for high-stakes decisions
- [x] Parallel shard execution with conflict reconciliation
- [x] Automated contract persistence (scripts/auto-persist.sh)
- [x] Automated 3-tier scoring pipeline (scripts/auto-score.sh)
- [x] Agent state guard verification (scripts/state-guard.sh)
- [x] Self-repair for corrupt contracts (scripts/self-repair.sh)
- [x] Knowledge vs file drift detection (scripts/drift-detect.sh)
- [x] SDD spec gate enforcement (scripts/sdd-gate.sh)
- [x] Knowledge persistence verification (scripts/verify-knowledge.sh)
- [x] Cross-session learning feedback loop (agents/orchestrator.md, learner.md)

See the [open issues](https://github.com/RizkiRachman/workflow-state-engine/issues) for a full list of proposed features and known issues.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Contributing

Contributions are what make the open source community such an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.

If you have a suggestion that would make this better, please fork the repo and create a pull request. You can also simply open an issue with the tag "enhancement".

1. Fork the project
2. Create a topic branch for your change
3. Commit your changes
4. Open a Pull Request

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## License

Distributed under the MIT License. See `LICENSE` for more information.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Contact

Rizki Rachman - [@RizkiRachman](https://github.com/RizkiRachman)

Project Link: [https://github.com/RizkiRachman/workflow-state-engine](https://github.com/RizkiRachman/workflow-state-engine)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Acknowledgments

This README follows the [Best-README-Template](https://github.com/othneildrew/Best-README-Template) by [@othneildrew](https://github.com/othneildrew).

Additional thanks to:

- [OpenCode](https://github.com/opencode-ai/opencode) — AI agent platform
- [lean-ctx](https://github.com/opencode-ai/lean-ctx) — compressed context management
- [lean-ctx](https://github.com/RizkiRachman/lean-ctx) — code intelligence graph
- [Graphify](https://github.com/safishamsi/graphify) — knowledge graph builder
- [Vercel Skills](https://github.com/vercel-labs/skills) — cross-agent skill packaging
- [Img Shields](https://shields.io) — badge generation
- [Choose an Open Source License](https://choosealicense.com) — license guidance
- [GitHub Emoji Cheat Sheet](https://www.webpagefx.com/tools/emoji-cheat-sheet)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- MARKDOWN LINKS & IMAGES -->
[contributors-shield]: https://img.shields.io/github/contributors/RizkiRachman/workflow-state-engine.svg?style=for-the-badge
[contributors-url]: https://github.com/RizkiRachman/workflow-state-engine/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/RizkiRachman/workflow-state-engine.svg?style=for-the-badge
[forks-url]: https://github.com/RizkiRachman/workflow-state-engine/network/members
[stars-shield]: https://img.shields.io/github/stars/RizkiRachman/workflow-state-engine.svg?style=for-the-badge
[stars-url]: https://github.com/RizkiRachman/workflow-state-engine/stargazers
[issues-shield]: https://img.shields.io/github/issues/RizkiRachman/workflow-state-engine.svg?style=for-the-badge
[issues-url]: https://github.com/RizkiRachman/workflow-state-engine/issues
[license-shield]: https://img.shields.io/github/license/RizkiRachman/workflow-state-engine.svg?style=for-the-badge
[license-url]: https://github.com/RizkiRachman/workflow-state-engine/blob/main/LICENSE