
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
