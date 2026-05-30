# devteam — TODOS

Deferrables that are explicitly **not** in v1.0.0. Each entry lists the trigger that should pull it from the backlog into a real task.

Format: `- [ ] <title> — <one-line context>` followed by **Trigger:** when to act.

---

## Tier 1 — likely to surface within 2-4 weeks of usage

- [ ] **Distribution CI/CD pipeline for devteam itself.** Currently ship via manual `git tag` + GitHub release + marketplace re-publish.
  **Trigger:** versioning becomes a chore (3+ manual releases in a month, or a release ships with a missed step).

- [ ] **Prompt regression eval suite (3a).** Lock in current prompt behavior before iterating, so regressions are caught quickly.
  **Trigger:** WATCHLIST signal `3a-malformed-output` (3 in 14 days) OR `3a-tier-flag-override` (5 in 14 days). See WATCHLIST.md.

- [ ] **Usage telemetry (3b).** Local-only JSONL at `~/.claude/devteam/telemetry/<date>.jsonl`. Records phase durations, classification decisions, retry counts, mode usage.
  **Trigger:** WATCHLIST signal `3b-manual-log` (2 in 14 days). See WATCHLIST.md.

## Tier 2 — useful but not urgent

- [ ] **Multi-project per repo.** Currently one active project at a time per `.devteam/state/`. Future: `.devteam/state/<slug>/` for parallel projects.
  **Trigger:** user wants to run two devteam projects against the same repo simultaneously.

- [ ] **Cross-session subagent memory.** Currently artifact-backed handover only. Future: optional persistent context for repeat-dispatched workers.
  **Trigger:** repeated re-dispatch of the same worker on related tasks shows that re-establishing context burns >20% of each turn.

- [ ] **Realtime / WebSocket review lens.** Folded into `supabase.md` initially.
  **Trigger:** Realtime patterns become a frequent review concern (3+ retros mentioning it).

- [ ] **DB seeding helper for tests.** Pattern doc lives in `supabase.md` test patterns section.
  **Trigger:** seeding logic gets duplicated across 2+ projects.

- [ ] **Background jobs / Supabase edge functions conventions.** Folded into `backend/supabase.md` initially.
  **Trigger:** edge-function patterns warrant their own file (3+ pages of supabase.md become edge-specific).

- [ ] **Multi-project context insights.** Surface patterns recurring across projects (e.g., "auth bug pattern hit in fieldwork AND dennis-web → write to global memory").
  **Trigger:** multi-project state lands first (Tier 2 above), then this becomes feasible.

## Tier 3 — defer indefinitely

- [ ] Web UI for slack viewing — slack.md in a text editor is fine.
- [ ] Multi-user / team-account features — solo developer for now.
- [ ] Cross-project telemetry — privacy concern; opt-in only if added.
- [ ] Windows-native support — WSL is the workaround.
- [ ] GraphQL conventions — no current projects use GraphQL.
- [ ] Project-specific conventions (Mapbox, react-pdf, signature, Resend, etc.) — keep these in per-project `CLAUDE.md`, not in devteam's conventions library. Library is for stacks reused across projects.
- [ ] Per-question tuning analog — gstack has `/plan-tune`; devteam could mirror it for funnel question preferences. Defer until funnel friction becomes a concrete pain.
- [ ] Plugin marketplace ecosystem (custom 3rd-party agents discoverable in devteam) — long-term roadmap.

## Tier 4 — design questions to revisit during execution

These were surfaced during plan-eng-review but deferred from v1.0.0 implementation.

- [ ] Convention library `index.json` maintenance: auto-generate from filesystem on LEAD start, vs hand-curated.
- [ ] Internal templates location: inline in LEAD skill body vs separate `templates/` files.
- [ ] Detail file cleanup policy in `slack-detail/`: archive alongside slack rotations vs separate retention.
- [ ] Memory write format from REFLECTOR: match existing auto-memory format.
- [ ] `/lead-show-entry <id>` falling back to archived slack files.
- [ ] Default project slug auto-derivation when user doesn't set one.
- [ ] Argument parsing rules: flags before task string vs anywhere.
- [ ] Pause + concurrent direct-specialist invocation behavior.
- [ ] `--mode <name>` flag scope: this run vs persistent.
- [ ] `${CLAUDE_PLUGIN_ROOT}` expansion behavior in subagent briefs (verify during impl).
- [ ] `VERSION` file vs `plugin.json#version` — single source of truth.
- [ ] `bin/slack-append.sh` executable bit handling (chmod +x in install).
- [ ] CHANGELOG.md initial seed automation.
- [ ] `/lead-setup-permissions` helper command (convenience over README block).
- [ ] Hook edge cases (permissions, missing files).
- [ ] Auto-detecting first install vs upgrade for `/lead-setup`.
- [ ] Conventions cleanup on plugin uninstall (orphaned global state).
- [ ] Corrupted state recovery (LEAD detects malformed slack/state).
- [ ] Exact "abandon" / "clear state" semantics (delete vs archive).
- [ ] 2.0.0 alias removal timeline for `/toolbox*` backward-compat.
