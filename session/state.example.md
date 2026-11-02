# STATE — Session Log (EXAMPLE)

> **This is a tracked EXAMPLE file.** Real session state lives in `session/state.md`
> (local-only, gitignored). Agents archive historical logs to `.session/`.
> Never commit or push real session history — it grows unbounded.
> Copy this skeleton to `session/state.md` when starting a fresh log.

---

## <YYYY-MM-DD> — <Task Title> (<agent>)

- Decisions:
  - <decision-one>
  - <decision-two>
- Blockers:
  - <blocker-or-none>

State: **<INIT> → <PLAN> → <PLAN_SCORED> → <EXECUTE> → <EXECUTE_SCORED> → <REVIEW> → <REVIEW_SCORED> → <COMPLETE>**

| Timestamp | Session | State | Score | Hash | Summary |
|-----------|---------|-------|-------|------|---------|
| `<YYYY-MM-DD HH:MM>` | `<session-id>` | INIT | — | — | Session initialised |
| `<YYYY-MM-DD HH:MM>` | `<session-id>` | PLAN_SCORED | `<0-100>` | `<short-sha>` | Plan accepted |
| `<YYYY-MM-DD HH:MM>` | `<session-id>` | COMPLETE | `<0-100>` | `<short-sha>` | Implementation complete |

Append-only. Local runtime copies of this log are never committed; archive growth
goes to `.session/`.
