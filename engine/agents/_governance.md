# Shared Governance — All Agents

This file is included by agent instruction files. It defines common governance rules,
permissions, and protocols that apply to every agent in the workflow-state-engine.

---
## 1. Contract Protocol

All agents **MUST** read the shared JSON envelope (`contract/contract.template.json`) at session start:

```lean-ctx
lean-ctx ctx_knowledge recall --key "orchestration-contract" --mode "exact"
```

- If found → extract `decisions.*`, `governance.*`, `retry.issues[]`, `scope.*`, `requirements.*`
- If NOT found (standalone session) → create fresh from `contract/contract.template.json`:
  1. Populate `session.task_id` (short slug like `"<agent-type>-standalone-<date>"`)
  2. Populate `session.created_at` (ISO timestamp)
  3. Persist: `lean-ctx ctx_knowledge remember key orchestration-contract value <JSON>`

The envelope is the single source of truth for session state, decisions, and outputs.
All agents read from it; write-capable agents update it with results.

---
## 2. Permissions

| Dimension | Rule |
|-----------|------|
| Shell commands | Use `lean-ctx ctx_shell` for **all** shell commands. `bash`/`snip` are denied in `opencode.json` — triggers permission prompts and blocks automation. |
| File reads | Prefer `lean-ctx ctx_read` (cached, compressed, ~13 tok re-reads). Use `lean-ctx ctx_search` for regex search. Native `read`/`grep` trigger permission prompts. |
| File edits | Use `lean-ctx ctx_edit` (search-and-replace) or `ctx_edit` with `create=true` for new files. Native `write`/`edit` tools are blocked. |
| **Read-only agents** | `product-manager`, `scrum-master`, `system-analyst`, `quality-analyst`, `security-engineer`, `learner`, `software-architect`, `explorer`, `librarian`, `council`, `observer` — **MUST NOT edit files**. |
| **Read-write agents** | `tech-lead`, `developer`, `fixer`, `devops-engineer` — may edit files within `scope.included`. |

### Agent Roster (scrum team)

| Agent | Mode | Contract States | Model Tier |
|-------|------|-----------------|------------|
| `tech-lead` | primary | all | executor |
| `product-manager` | subagent | INIT, PLAN | **reviewer** |
| `scrum-master` | subagent | all, BLOCKED | **reviewer** |
| `system-analyst` | subagent | INIT, PLAN, PLAN_SCORED | executor |
| `software-architect` | subagent | INIT, PLAN, REVIEW | **reviewer** |
| `developer` | subagent | EXECUTE, EXECUTE_SCORED | executor |
| `devops-engineer` | subagent | EXECUTE, EXECUTE_SCORED, REVIEW | executor |
| `quality-analyst` | subagent | REVIEW, REVIEW_SCORED | **reviewer** |
| `security-engineer` | subagent | REVIEW, REVIEW_SCORED | **reviewer** |
| `explorer` | subagent | all | executor |
| `librarian` | subagent | all | executor |
| `council` | subagent | all (high-stakes) | **multi** |
| `observer` | subagent | all | executor |
| `fixer` | subagent | EXECUTE | executor |
| `learner` | subagent | REVIEW_SCORED, COMPLETE | executor |

**Model tiers**: executor = `opencode/big-pickle`; reviewer = `sumopod/deepseek-flash` (independent model); multi = both. Reviewers never share the executor's model — this is the basis of cross-model review (see `rules.json → enforcement.cross_model_review`).

---
## 3. Session Lifecycle (Contract Archival)

Every orchestration session MUST persist its contract state to the `session/` directory for cross-session traceability and resumption.

### Directory layout

```
contract/                    ← Committed definitions (version-controlled, all files tracked)
  contract.schema.json        JSON Schema for the orchestration envelope
  state.md                    Session state template
  contract.template.json      Seed envelope for fresh sessions

session/                     ← Live state + archive (append-only state log + contract.json + archive/)
  state.md                   ← Append-only log of ALL state transitions (every session)
```

### Lifecycle Protocol

| Event | Action |
|-------|--------|
| **State transition** | Update envelope in `lean-ctx ctx_knowledge` → snapshot to `session/` via `scripts/snapshot-contract.sh` |
| **Session end** (COMPLETE/BLOCKED) | Run final snapshot → append summary to `session/state.md` |
| **Session resume** | Load `session/contract.json` + `session/state.md` → continue from persisted state |

### Snapshot command

```bash
# Full snapshot (copies contract files + updates state.md)
bash scripts/snapshot-contract.sh --summary "State: ${STATE} — brief description"

# Files-only (skip index updates for hot-reload scenarios)
bash scripts/snapshot-contract.sh --snapshot-only

# Preview without writing
bash scripts/snapshot-contract.sh --dry-run --verbose
```

### Why

Without per-session archival, contract files get overwritten when a new session overwrites it. The `session/` archive preserves:
- **Resumability**: The last persisted state is restorable at any time
- **Audit trail**: `session/state.md` grows monotonically — every state transition, ever
- **Discoverability**: `session/state.md` shows the full transition history at a glance

## 4. Pre-Edit Safety (write-capable agents only)

Before editing **any existing symbol** (function, class, method):

1. **Impact analysis** — `ctx_impact({target: "symbolName", direction: "upstream"})`
   - Report blast radius (direct callers, affected processes, risk level)
2. **HIGH/CRITICAL warning** — if impact returns HIGH or CRITICAL risk, **warn the user** before proceeding
3. **Detect changes** — `ctx_delta()` before committing to verify only expected files changed
4. **Never rename with find-and-replace** — use `ctx_refactor` which understands the call graph

---

Run this ladder in order before writing ANY code:

1. Does this need to exist? → skip it (YAGNI)
2. Standard library does it? → use it
3. Already-installed dependency? → use it
4. Can this be one line? → one line
5. Only then: minimum code that works

**Rules:** No unsolicited abstractions. No new deps if avoidable. Deletion > addition.
comments (ceiling + upgrade path).

**Not sacrificed:** Input validation at trust boundaries, data-loss error handling,
security, accessibility, anything explicitly requested. Non-trivial logic leaves
ONE runnable check (assert-based, no test framework).

---
## 6. Post-Flight Protocol (before commit)

After completing work, run these steps **in order**:

| # | Step | Tool |
|---|------|------|
| 1 | Impact verification | `ctx_impact({target, direction: "upstream"})` — confirm blast radius matches expectations. If HIGH/CRITICAL, note in output. |
| 2 | Change detection | `ctx_delta()` (or `{scope: "all"}` for staged+unstaged) — verify only expected files changed, no unintended side effects. |
| 3 | Knowledge persistence | `lean-ctx ctx_knowledge remember` — persist gotchas, patterns, decisions (categories: `architecture`, `gotchas`, `conventions`). |
| 4 | STATE.md update | `lean-ctx ctx_edit` on `session/state.md` — append completed work, update Current Focus, update Known Blockers. |
| 5 | Session save (complete) | Run **Save Session Protocol** — persist envelope → update state.md → archive snapshot → save conversation → re-index lean-ctx → re-index graphify |

**Exceptions:** Documentation-only changes may skip steps 1, 2, and 4. Config-only changes skip 1, 2.

### Save Session Protocol

When the user says "save session" or a phase completes, save to **ALL** systems:

```bash
# 1. Persist orchestration envelope to lean-ctx knowledge
lean-ctx ctx_knowledge remember key orchestration-contract value "<JSON>"

# 2. Update session/state.md — append completed work items

# 3. Archive snapshot to session/ (contract files + state log + index)
bash scripts/snapshot-contract.sh --snapshot-only

# 4. Save conversation context (survives OpenCode restart)
lean-ctx ctx_session save

# 5. Re-index lean-ctx code intelligence
bash graphify --update

# 6. Re-index Graphify knowledge graph (if graphify-out/ exists)
graphify --update 2>/dev/null || true
```

**One-shot alias**: `save session` = all 6 steps above. Always run the full protocol — partial saves lose audit trail, break resumption, or leave stale indexes.

---
## 7. Communication

- Explain tradeoffs, not just decisions
- Admit unknowns — be clear about what you don't know
- Be **token-efficient**: concise, no filler, no full-file dumps
- Return only what was asked — don't expand scope
- Use fragments where clear, revert to full sentences for security warnings and destructive operations
