
## 2026-10-20 - Config & Toolkit Update (tech-lead)

- Primary agent: default_agent=build; agent.build -> model opencode/big-pickle, mode=primary (all 4 workspace configs).
- _governance: removed the vestigial disabled agent key (agents/_governance.md doc kept - referenced by docs/validation).
- MCP: graphify disabled (enabled:false). Wired memory + fetch (enabled) from the image; everything added but enabled:false (demo server). Active MCPs: lean-ctx, context7, memory, fetch.
- Skills frontmatter (finding E): 24 files desc: -> description:; humanizer + adaptive-solver wrapped in --- fences with name:. Applied to BOTH engine/skills and /opt/engine/skills; verified 0 remaining ^desc: and all SKILL.md start with ---.
- Subagent permissions (finding B): read-only agents (11) now have read/grep/glob/list/lean-ctx_*/context7_*/memory_* (edit/write/bash denied); read-write agents (developer, devops-engineer, fixer) additionally edit/write allowed. Delegation unblocked.
- Plugins: aligned to 3 (model-fallback, dcp, websearch-cited) across all configs.
- Drift (finding G): engine/ synced to /opt/engine/; only remaining delta is the intentional extra deployed lean-ctx skill.
- Docs: verified model-tier claims now match runtime (executor=big-pickle via build, reviewer=deepseek); lean-ctx 1675-symbol claim is genuine index stat, not stale.

- State: COMPLETE. Restart opencode to load the new config (config file is bind-mounted ro; skills/engine changes are live now).

## 2026-10-30 — Documentation/consistency drift audit (developer standalone)
- Drift audit performed across engine/skills, engine/agents, engine/agent.md, READMEs, opencode.json.template.
- Skill count normalized to 63 (agent.md x3, engine/README.md x1, README.md 65+ -> 63).
- engine/skills/taste-skill renamed to design-taste-frontend (dir name now equals SKILL.md name: frontmatter); ui-ux-tech-lead.md references updated (2 occurrences).
- agent.md §7 table completed: 7 missing rows added (commit, gradle-test-runner, ralph-coverage, rebase-commit, restart-spring-boot, shipping-and-launch, spec); bogus lean-ctx-{exploring,impact,...} line replaced with a single lean-ctx row (63 rows = 63 dirs).
- Model IDs unified to provider map keys: deepseek-v4-flash -> deepseek-flash repository-wide (agent.md, agents/_governance.md, rules/rules.json, usage/opencode.md, doc/project.md, doc/workflow/03-agents.md, README.md, opencode.json.template); agent count normalized to 16 across the docs; README.md env defaults now sumopod/glm-5.3-flash / glm-5.3-flash (matches config/opencode.json default, deepseek-flash fallback kept); template gains glm-5.3-flash model entry { "name": "GLM 5.3 Flash" }.
- Deployed /opt/engine/skills/lean-ctx copied into engine/skills/lean-ctx (source tree now has all 63 skills).
- agent.md §3: quality-analyst MCPs corrected to lean-ctx (no postgres MCP in config).
- context7 flip is handled separately by the user; everything MCP remains enabled in config (docs now match).
- Files changed: engine/agent.md, engine/README.md, README.md, engine/agents/ui-ux-tech-lead.md, engine/opencode.json.template, engine/skills/lean-ctx/ (new), engine/skills/design-taste-frontend/ (renamed), session/state.md.
- State: COMPLETE
- Added `awesome-pr` skill + `.github/PULL_REQUEST_TEMPLATE.md`; skill count 64.
