# Changelog

## 1.1.0 — 2026-05-30 — Save/continue session state management

### Added
- `/save [name?]` — capture session state as a curated savepoint at `~/.claude/devteam/saves/<slug>/latest.md` with optional decisions sidecar. Layered design (~1500 tokens main + ~3000 tokens sidecar on demand), enforced size caps, rolling 10-entry history, named save slots.
- `/continue [name|latest|list?]` — resume from a savepoint; subsumes the prior `/lead-resume` by surfacing any pending `WAITING ON USER` block and offering to answer it inline.
- `hooks/save-autosave.sh` — Stop + SessionEnd hook with change-based gating (writes only when git HEAD or slack mtime changes) and 10-minute clobber protection against fresh explicit saves. Prints `📦 autosaved` on write.
- `hooks/save-reminder.sh` — Stop hook mirroring handoff's pattern: nags once per session when commits land without a `/save` since `.last-explicit` marker.
- `hooks/session-start.sh` — extended to surface existing saves on session entry (`📌 Save exists for this project ...`).

### Removed
- `/lead-resume` — functionality folded into `/continue` (which auto-surfaces pending blocks).
- `/lead-abort` — functionality folded into `/save` (saving is the gravestone; no consumer left for `.last-phase=aborted`).

### Changed
- `/lead-setup` now registers Stop and SessionEnd hooks in addition to SessionStart. Existing setups remain idempotent — re-running picks up the new hook registrations.
- `.claude-plugin/plugin.json` version bumped 1.0.1 → 1.1.0.

### Migration notes
- Existing devteam users: run `/lead-setup` to register the new hooks (idempotent).
- claude-sync users on `/handoff` and `/continue-work`: those still work; deprecation lands in claude-sync after a 2-week / 15-session validation period with the new devteam commands (Phase 4).

## 1.0.1 — 2026-04-28 — Per-agent model selection

### Added
- **Per-agent `model:` defaults** in all 7 worker/utility agent frontmatter (builder, review-specialist, tester, explorer, critic, synthesizer, investigator). Sensible defaults: `sonnet` for code-reasoning roles (builder, review-specialist, explorer, critic, investigator); `haiku` for mechanical roles (tester, synthesizer).
- **Per-lens `model:` overrides** via new YAML frontmatter on all 6 review-lens spec files. `data-migration` always uses `opus` (high prod-risk work); `security`, `perf`, `api-contract` use `sonnet`; `testing` and `a11y` use `haiku`.
- **`--model <name>` flag** on `/lead` (values: `sonnet | opus | haiku`). Run-level override for all worker dispatches. Persisted to `.devteam/state/.flags` for the run. Skills (THINK/PLAN/SHIP/REFLECT) are unaffected — they run in the main thread and inherit the user's session model.
- **Model selection cascade** documented in `skills/lead/SKILL.md` §5.5 and `dispatch-recipes.md`: `--model` flag → lens-spec override → agent frontmatter default → inherit.

### Why
Without explicit defaults, all parallel-fanout dispatches inherited the user's session model (typically Opus). For complex-tier features that fan out 8–12 workers in parallel, this caused materially wasteful spend on roles that don't need Opus reasoning (e.g., test runners, a11y checklist reviewers). The new defaults route Opus to where it earns its keep (data-migration review) and Haiku to where it's enough (tester, synthesizer).

### Notes
- Existing v1.0.0 behavior is preserved when no `--model` flag is used and no agent frontmatter changes are made downstream — the cascade falls through to inherit, matching pre-1.0.1 behavior. The new defaults take effect on plugin upgrade.
- No state migration needed. `.devteam/state/.flags` is read-only created when the user passes `--model`.

## 1.0.0 — TBD-2026-04-XX — Multi-agent team redesign (rename: toolbox → devteam)

### Major
- **Plugin renamed**: `toolbox` → `devteam`. Clean break (parallel install). Old `toolbox` should be uninstalled before installing devteam.
- **LEAD orchestrator skill** — single user-facing persona. LEAD dispatches workers in parallel via the Task tool directly (no lead-agent middleware; per A1-final, lead-agents removed as vestigial once they couldn't dispatch nested subagents).
- **5 dialogue skills**: LEAD, THINKER, PLANNER (with `/autoplan` delegation in work-together mode and DESIGN.md-aware planning), SHIPPER (chains `/document-release`), REFLECTOR (tier-gated retros + watchlist integration).
- **7 worker agents**: BUILDER, review-specialist (with 6 lens spec files: security, perf, testing, a11y, data-migration, api-contract), TESTER, plus 4 utility agents (EXPLORER, CRITIC, SYNTHESIZER, INVESTIGATOR).
- **Two invocation modes**: `/lead` orchestrated + 7 direct specialist commands (`/think`, `/plan`, `/build`, `/review-project`, `/test`, `/ship-project`, `/reflect`).
- **Two autonomy modes**: Work-Together (default) and Autonomous (halts cleanly with notification on hard-blocked questions).
- **Team Slack** — append-only chronological audit log per project. Race-safe via mkdir-mutex with stale-lock detection (POSIX-portable, no flock dependency). Per-actor counters for collision-free IDs.
- **Wave-grouped partitions** — PLANNER produces `plan-partitions.md` with `dependencies: []` and `parallel_safe: true|false`. LEAD reads waves and dispatches BUILDERs in parallel per wave (per A1-final).
- **REVIEW lens selection** — `bin/devteam-pick-lenses.sh` runs deterministic regex over `git diff --name-only` to return applicable lenses (security, perf, testing, a11y, data-migration, api-contract).
- **TEST layer detection** — `bin/devteam-detect-stack.sh --tests` returns test layer names per project.
- **Watchlist mechanism** — `bin/devteam-watchlist.sh` analyzes slack for mechanical signals (`3a-malformed-output`, `3a-tier-flag-override`, `3b-manual-log`); thresholds in `WATCHLIST.md`. Replaces immediate eval/telemetry implementation; tells the user when deferred features become worth implementing.
- **Per-project state** at `.devteam/state/`, **global memory** at `~/.claude/devteam/memory/`, **conventions library** at `~/.claude/devteam/conventions/` (8 stacks seeded: Pine Script, React, Tailwind, Next.js App Router, Node, Supabase, Postgres, Claude Code plugin authoring).
- **SessionStart hook** (opt-in via `/lead-setup`) shows project status when entering a repo with active state.
- **Question-packet contract** with 3 states: `complete | blocked | failed`. Retry-once-then-escalate on failure.

### Backward compatibility
- `/toolbox*` commands preserved as deprecated routers (will be removed in 2.0.0). Five wrappers route to `/lead` with `--tier <name>`.

### Requirements
- superpowers (>= 5.0.0)
- gstack (recommended; optional)
- macOS / Linux / WSL

### Hard rules
- Destructive actions always confirm, both modes.
- Twice-failed specialist always escalates, both modes.

## 0.1.0 — 2026-04-XX — Initial release (as `toolbox`)

- 5-skill workflow router: `toolbox` + `toolbox-{simple,bug,feature,complex}` playbooks.
