# devteam Architecture — Design Rationale

For contributors and anyone working on devteam 6 months from now wondering "why did they do it this way?"

This document explains the WHY behind the architecture. For WHAT it does, see README.md.

---

## The team metaphor — why it matters

The "virtual dev team" framing is not decoration. It does two concrete things:

1. **Names map to familiar roles.** LEAD, BUILDER, TESTER, REFLECTOR — these words carry existing expectations. A new contributor reading `agents/builder.md` already has a mental model before they open the file. Naming roles "AgentA / AgentB" or "Orchestrator / Worker" forces readers to build a model from scratch.

2. **Separation of concerns is explicit.** In a real team, you don't tell the QA engineer to also write the feature. The same principle guides which agent handles which phase. BUILDER doesn't run tests. TESTER doesn't review for security. This makes the boundary conditions obvious when something goes wrong — and when something goes well.

The product-owner / tech-lead framing (user = PO, LEAD = tech lead) is also intentional: it explains why LEAD presents recommendations rather than just relaying raw specialist output. A tech lead synthesizes; they don't just pass notes.

---

## Why no lead agents (A1-final)

Early design included BUILD-LEAD, REVIEW-LEAD, and TEST-LEAD: coordinator agents sitting between LEAD and the workers. The idea was:

- BUILD-LEAD would split partitions, dispatch BUILDERs in parallel, and merge results before returning to LEAD.
- REVIEW-LEAD would select lenses, dispatch review specialists in parallel, and merge JSON findings.
- TEST-LEAD would dispatch TESTERs per test layer and aggregate.

This was removed at A1-final, after an outside-voice architecture review identified a fundamental problem: **subagents in Claude Code cannot dispatch nested subagents**. A Task-tool agent runs in a fresh context without access to the Task tool itself. So BUILD-LEAD could not actually dispatch BUILDERs — only LEAD (running in the main thread as a skill) can use Task tool.

Once the nesting doesn't work, the lead-agents become vestigial wrappers. They add a latency hop and a context-copy cost with no benefit. The correct model is:

- LEAD reads `plan-partitions.md` directly and dispatches BUILDERs per wave in parallel via Task tool.
- LEAD selects lenses via `bin/devteam-pick-lenses.sh` and dispatches review-specialist instances in parallel.
- LEAD calls TESTER directly for each detected test layer.

This is what A1-final locked in. If Claude Code ever gains nested Task dispatch, the lead-agent coordinator pattern could be revisited — but for now it's both correct and simpler.

---

## The skill-vs-agent rule

> If the role's core work involves dialogue with the user, it's a skill. If it's heads-down or parallelizable, it's an agent.

This distinction matters because:

- **Skills** run in the main conversation thread. They can call AskUserQuestion. They preserve the conversation arc. They load LEAD's context.
- **Agents** run in fresh subagent contexts via Task tool. They don't have access to conversation history. They can run in parallel. They return structured packets.

The five skills (LEAD, THINKER, PLANNER, SHIPPER, REFLECTOR) all have phases where they need to interact with the user — asking questions, presenting options, confirming before shipping. Putting them in agent files would mean LEAD always has to relay every message, adding noise.

Workers (BUILDER, review-specialist, TESTER) do heads-down implementation, linting, or testing. They don't need to ask the user anything — when they hit a blocker, they return a `blocked` packet. The four utility agents (EXPLORER, CRITIC, SYNTHESIZER, INVESTIGATOR) are inherently parallel-capable: you can fan out three EXPLORERs simultaneously, which only works if they're agents.

A skill CAN dispatch agents internally (e.g., THINKER dispatches EXPLORER instances in shotgun mode). An agent cannot dispatch other agents. This asymmetry is why the rule is stated in terms of the role's primary work, not its use of agents.

---

## The funnel rule

Workers in LEAD mode never call AskUserQuestion directly. When a specialist hits something it can't decide, it returns a `blocked` packet to LEAD. LEAD then:

1. Adds its own recommendation (in addition to the specialist's recommendation).
2. Presents the question to the user in a structured format.
3. Re-dispatches the specialist with the answer.

This is the tech-lead funnel: you as the product owner talk to your tech lead, not to every individual contributor. The funnel has two concrete benefits:

- **LEAD's context is complete.** LEAD can add global-memory context or project-history context that the specialist doesn't have.
- **Interaction is coherent.** If BUILD and REVIEW both have questions, they queue through LEAD rather than interrupting you in parallel.

In direct mode (`/think`, `/build`, etc.), the funnel rule does NOT apply. When you invoke a specialist directly, you ARE the user interface, and the specialist talks to you directly.

The question packet schema lives at `docs/question-packet.md` and `docs/question-packet-schema.json`.

---

## The slack contract

Every actor appends to `.devteam/state/slack.md`. The key design decisions:

**Append-only.** No actor edits or deletes slack entries. This makes the audit trail trustworthy and the concurrency model simple.

**One file per project.** The entire team shares one log. Searching it is a single grep; understanding what happened across phases requires no file-joining.

**mkdir-mutex.** Race safety without `flock` (which isn't POSIX-portable and behaves differently on macOS vs Linux). `bin/slack-append.sh` does `mkdir "$LOCKDIR"` atomically; only the process that succeeds proceeds. The lock directory is removed on `EXIT` trap. Stale locks (from crashed processes) are detectable by age. This is the classic POSIX mutual-exclusion pattern; it works reliably across platforms.

**Per-actor counters.** Multiple parallel BUILDERs appending simultaneously with second-granularity timestamps would produce colliding IDs (BSD `date` on macOS doesn't support `%3N` for milliseconds). Instead, each actor carries a sequence counter (`[BUILDER:fe#01]`, `[BUILDER:fe#02]`). The counter is per-actor-per-session, not global, so no coordination is needed. Combined with the timestamp, IDs are unique.

**Rolling archive.** At 2000 lines / 200 KB, the current file becomes too slow to scan. `bin/slack-append.sh` handles rotation by moving the current slack to `state/archive/slack-<date>.md` and starting fresh. In-progress phase entries are preserved in the new file.

---

## The watchlist mechanism

WATCHLIST.md defines threshold-based signals for deferred features. The key design choice: **mechanical signals only**.

Early proposals included signals like "LEAD overrides its own classification" or "user expresses frustration" — both require LLM judgment to detect, which is unreliable and noisy. The watchlist uses only:

- Exact-string match: `3a-malformed-output` — logged by LEAD when a returned packet fails schema validation.
- Counter: `3a-tier-flag-override` — logged by LEAD when `--tier` is explicitly passed.
- User-initiated: `3b-manual-log` — user runs `bin/devteam-watchlist-log.sh` to record a concern.

`bin/devteam-watchlist.sh` counts these entries in the trailing 14-day window across `slack.md` and `archive/*.md`. When a threshold is crossed, the user sees an `ALERT` recommending they pull the feature from TODOS.md into a real task.

This replaces the "build eval/telemetry immediately" approach: instead of building infrastructure before knowing it's needed, the watchlist tells you when the need has been demonstrated. The features are in TODOS.md with their triggers; the watchlist is what turns the trigger into an alert.

---

## Persistence model

Subagents in Claude Code have fresh contexts — they don't share memory with the main thread or each other. Devteam's persistence model is entirely artifact-backed:

- **State files** (`state/think.md`, `state/plan.md`, etc.) are the handover medium. A BUILDER agent reads `state/plan.md` and `state/plan-partitions.md` as its brief.
- **LEAD writes `.devteam/state/.plugin-path`** on startup so subagent briefs can reference bin scripts by absolute path.
- **No long-running subagents.** Each dispatch is fresh. Context is reconstructed from artifacts.

This is simpler and more reliable than trying to maintain persistent agent state across sessions. The cost is that agents can't "remember" previous dispatches from this session directly — they reconstruct from files. In practice this works well because the artifacts are comprehensive.

Cross-session memory is handled separately via `~/.claude/devteam/memory/` (REFLECTOR appends lessons; LEAD reads at startup) and conventions library (BUILDER auto-loads stack conventions from `~/.claude/devteam/conventions/`).

**Cross-session recovery** is handled by `/checkpoint` (renamed from `/save` in 1.2.0) and `/continue`. Checkpoints live at `~/.claude/devteam/checkpoints/<slug>/` — the third leg of the global-tier persistence (alongside `memory/` lessons and `conventions/` stack guidance). Checkpoints are layered (minimal `latest.md` + optional `latest-decisions.md` sidecar) with enforced size caps and rolling 10-entry history per project. A change-based Stop autosave hook protects against crashes between explicit checkpoints.

This is the *tool-layer* recovery mechanism — machine-local, per-cwd, public. Complementary to a separate *user-layer* mechanism that may exist in user-personal vaults (e.g., a brain vault). The user-layer `/save` writes a single canonical project state to the vault; the tool-layer `/checkpoint` writes rolling per-session recovery points to local devteam storage. Different audiences, different durability, different cardinality.

---

## Per-tier phase subsets

Not every task needs all 7 phases. Running THINK + PLAN for a one-line typo fix is overhead. The tier system:

| Tier | Phases | Rationale |
|---|---|---|
| simple | BUILD + TEST | No design needed; minimal review surface |
| bug | THINK(lite) + BUILD + TEST + REVIEW | Root-cause analysis needed; review catches regression risks |
| feature | THINK + PLAN + BUILD + REVIEW + TEST + SHIP | Full design + safe delivery |
| complex | All 7, parallel BUILD fan-out | Max thoroughness; REFLECT captures lessons for future projects |

REFLECT tier-gating is particularly deliberate: for a simple bug fix, a full retrospective is noise. For a complex multi-week project, skipping retrospective means losing the most valuable lessons.

LEAD decides the tier based on task description. Users can override with `--tier <name>`. If LEAD is borderline, it runs two EXPLORER instances to argue both sides before deciding.

---

## Two-axis modes

Invocation mode (LEAD vs direct) and autonomy mode (work-together vs autonomous) are independent axes:

- **Invocation** is per-call. You can invoke LEAD for full orchestration or any specialist directly without using LEAD at all.
- **Autonomy** is per-project, persisted in `.devteam/mode`. It controls how much LEAD checks in.

These were initially a single dimension but split early: you might want LEAD orchestration with heavy supervision (work-together), or you might want to invoke BUILDER directly for a quick edit in autonomous fashion. The axes are orthogonal.

Hard rules (destructive actions always confirm; twice-failed always escalates) apply in BOTH modes. There is no autonomy level that bypasses these. This is deliberate: the downside of a missed confirmation on `DROP TABLE` is catastrophic and irreversible; the cost of a confirmation prompt is trivial.

---

## Why some original ideas were dropped

**Lead-as-skill loaded into LEAD's turn.** Early design explored making THINKER, PLANNER etc. "loadable into LEAD's turn" (i.e., LEAD would directly execute their SKILL.md content rather than dispatching them). This was rejected because it conflated LEAD's orchestration logic with the phase-specific logic. Keeping them as separate skills means each can be tested in direct mode independently, and LEAD's body stays focused on dispatch logic.

**LLM-judgment watchlist signals.** Proposed signals like "user corrected LEAD's classification" required detecting user intent from natural language — inherently unreliable. All surviving signals are mechanical (schema validation failure, flag presence, user-initiated write). If a need emerges for behavioral signals, prefer adding exact-string match patterns over intent detection.

**Cross-session memory for subagents.** Tempting but deferred. The implementation complexity (persisting context, invalidating stale context, format compatibility across model versions) is high. The artifact-backed model is sufficient for v1 and covers the common case (BUILDER reads plan, writes code, done). Revisit if the 20%-context-reconstruction threshold in TODOS.md is hit.

**`/lead-resume` and `/lead-abort` as separate commands.** Both were narrowly scoped: `/lead-resume` only handled the WAITING-ON-USER block case; `/lead-abort` only set a `.last-phase=aborted` marker no one consumed. Once `/save` + `/continue` arrived in 1.1.0, both became redundant — `/continue` surfaces pending blocks automatically, and `/save` IS the abort artifact (you save state and walk away). Removed in 1.1.0.

**`/save` as the devteam command name.** Shipped in 1.1.0 as `/save`. Renamed to `/checkpoint` in 1.2.0 (breaking) because the name `/save` is more intuitive for the singular canonical state — which is what a user-personal brain/vault layer naturally owns. Devteam's actual function (many recovery points per session, rolling history, machine-local) matches "checkpoint" better. Conventional intuition wins over the original choice.

---

## Where to look when extending

| You want to... | Look here |
|---|---|
| Change how LEAD orchestrates or classifies | `skills/lead/SKILL.md` |
| Change a phase's behavior | `skills/<phase>/SKILL.md` (THINKER, PLANNER, SHIPPER, REFLECTOR) |
| Change how a worker operates | `agents/builder.md`, `agents/tester.md`, etc. |
| Add or modify a review lens | `agents/review-lenses/`, `bin/devteam-pick-lenses.sh` |
| Add a convention stack | `conventions-seed/<category>/`, `conventions-seed/index.json` |
| Change slack format or rotation | `bin/slack-append.sh` |
| Add a watchlist signal | `WATCHLIST.md`, `bin/devteam-watchlist.sh` |
| Add a deferred feature with a trigger | `TODOS.md` + `WATCHLIST.md` |
| Add a new command | `commands/<name>.md` (and update command count in README) |
| Understand state file layout | `docs/state-files.md` |
| Understand question-packet contract | `docs/question-packet.md`, `docs/question-packet-schema.json` |
| Understand mode behavior | `docs/modes.md` |
