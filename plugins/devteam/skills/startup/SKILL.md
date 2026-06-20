---
name: startup
description: Use to run a project on full autopilot — give it a goal and it drives THINK→DESIGN→PLAN→BUILD→REVIEW→TEST autonomously, using council-lite to decide and tapping you only on escalation gates (breaking, monetary, security, token-budget, destructive). Stops at the ship boundary. Interrupt anytime to inject decisions, redirect, or stop. Invoke via /startup. Distinct from /lead — startup runs unattended on a contract; /lead checks in.
---

# STARTUP — autonomous project autopilot

You drive a project from goal to ready-to-ship with minimal human input. You run in the main thread (you are the orchestrator); you dispatch specialists via the Task tool and invoke other skills (`council`, presto `magic`/`design-audit`, `checkpoint`) via the Skill tool. You REUSE LEAD's phase recipes — you do not replace or modify LEAD.

Read this whole skill before acting. The run is governed by a CONTRACT the user approves once, then a small set of GATES that are the only things allowed to interrupt the user.

## 0. Boot

- Ensure `.devteam/state/` exists; resolve the absolute plugin path and write it to `.devteam/state/.plugin-path`.
- Read the current `.devteam/mode`; remember it. Force `mode = autonomous` for this run (write `.devteam/mode`). Restore the remembered value on exit.
- Initialise `.devteam/state/.dispatch-count` to `0`.
- Parse flags from the command brief: budget (default 40), fanout (default 4), tier, ship (bool), no-images (bool), notify (default true), goal-file.
- Write `.devteam/state/.startup` policy file (one `key=value` per line: `budget`, `fanout`, `ship_boundary`, `images`, `notify`).
- Dependency check (read `~/.claude/plugins/installed_plugins.json`): `superpowers` REQUIRED (refuse if missing); `gstack` soft; `presto` soft — if absent, the DESIGN phase will be skipped with a warning.

## 0.5 INTAKE (only when no goal was provided)

If the command handed you **no goal string AND no `--goal-file`**, do NOT stop — run goal-intake to co-author one. (If a goal WAS provided, skip this entire section and go to §1.)

### Q&A (default — 0 dispatches)
Ask the user in ONE short round (use `AskUserQuestion` for the choice questions, prose for the open ones — do not interrogate):

1. **What are you building?** (one sentence). Offer an explicit escape option: **"I'm not sure — help me shape it."**
2. **Project type?** — web app / mobile app / CLI / API / library / other.
3. **Hard constraints?** (stack, must / must-not, deadline) — optional.
4. **Scope of this first run?** — the whole thing / a foundational slice / a specific feature.

### Unsure → council-lite deferral (opt-in, ~5 dispatches)
If the user picks **"I'm not sure — help me shape it"** on Q1, OR gives empty/too-thin answers to all four questions, convene `council --lite` (Skill tool) to **propose 1–3 candidate goal directions** — synthesis goal stated verbatim: "Propose 1–3 concrete goal directions for this project; do NOT verdict." Brief it with the partial answers + project context: cwd, `git` state, the repo `README`, and the vault-project `CLAUDE.md` if the cwd basename matches a vault project. Add the dispatches to `.devteam/state/.dispatch-count` and log `[STARTUP#] INFO  INTAKE council-lite: proposing goal directions` (per §7). Present the candidates; the user picks one and edits it (allow one more round if asked).

### Assemble + write GOAL.md
Compose the confident answers (or the chosen candidate) into a goal brief — intent, deliverables, scope, out-of-scope, stack preference if given (the same shape as any `--goal-file`). Write it to `./GOAL.md`, echo it to the user, and note it is committed-ready. Do NOT `git commit` it here — BUILD/SHIP commit it with the rest; INTAKE stays side-effect-light. Use this goal for §1.

### Hard fallback
If the user declines even the unsure path (fully empty), ask once more; if still nothing, exit cleanly: "Give me a goal or a `--goal-file` to start." Never loop.

## 1. CONTRACT phase (the one guaranteed up-front gate)

1. Convene `council --lite` (Skill tool) on the goal (provided by the command, or assembled in §0.5 INTAKE). Brief it to produce a CONTRACT covering: refined goal; success criteria; recommended tier + phase plan; whether a DESIGN phase is needed (is this UI/presentation work?); the escalation gates; the dispatch budget + a PROJECTED dispatch count for the plan; the ship boundary; and the top 3 risks. (This council convening counts ~5 dispatches — add them to `.dispatch-count`.)
2. Present the CONTRACT to the user, then ask: approve / edit / cancel.
   - edit → incorporate and re-present.
   - cancel → restore the prior mode, exit.
   - approve → write `.devteam/state/contract.md`; log `[STARTUP#] DECISION  contract approved`; engage autopilot.

## 2. Autopilot loop

Run phases in order, STOPPING before SHIP. For each phase follow LEAD's recipe (`skills/lead/SKILL.md` "Phase-by-phase orchestration" + `skills/lead/dispatch-recipes.md`) in autonomous mode, with the overrides below.

Phases: THINK → [DESIGN, if UI] → PLAN → BUILD → REVIEW → TEST.

**Before EVERY wave of Task dispatches:**
- Compute `projected_wave_size` (how many agents you are about to dispatch in this wave).
- Read `.devteam/state/.dispatch-count`. If `count + projected_wave_size > budget` → TOKEN gate (§4).
- Otherwise dispatch the wave, then add the number actually dispatched to `.dispatch-count`.

**At EVERY phase boundary:**
- Read `.devteam/control` (§5); act on `STOP` / `REDIRECT`, then clear it.
- Run `/checkpoint` (Skill) to save resumable state.
- Show a one-line status + running dispatch count + soft token estimate (`count × 15000` output tokens, labelled "rough estimate — not metering").

### Phase specifics

- **THINK** — run the `thinker` recipe. Framing ambiguity → council-lite (§3).
- **DESIGN** (only if the contract says UI; requires presto) — MAIN THREAD: invoke presto `/magic` (Skill) on the design brief. It produces `tokens.css`, `DESIGN_APPROACH.md`, and the design system. Every image-generation batch inside magic → MONETARY gate (§4); pass `--nogen` to magic if `images=false` in policy. If presto is absent → log a warning, skip DESIGN, proceed.
- **PLAN** — run the `planner` recipe → `state/plan-partitions.md`. Architecture/spec decisions → council-lite (§3). Mark UI partitions (frontend paths) so BUILD routes them to `frontend-specialist`.
- **BUILD** — per wave (respect `fanout`): dispatch `builder` for non-UI partitions and `frontend-specialist` for UI partitions, in parallel. UI briefs include the DESIGN artifact paths + the presto taste-skill paths. Merge/commit diffs serially after each wave.
- **REVIEW** — `review-specialist` per lens (`bin/devteam-pick-lenses.sh`). If UI was built and presto is present, also run presto `/design-audit` (Skill, main thread) on the UI. A `review-specialist:security` CRITICAL finding → SECURITY gate (§4).
- **TEST** — `tester` per layer (`bin/devteam-detect-stack.sh --tests`).

## 3. Decider policy

- Full `council --lite` (Skill) at: goal/contract framing, tier classification, architecture/spec decisions, and any specialist `blocked` packet that is genuinely consequential.
- Cheap pre-flight (`1× explorer` + `1× critic` = 2 agents, matching LEAD's §7 autonomous "Pre-flight w/ CRITIC + EXPLORER") for small in-phase micro-ambiguities.
- Use the verdict to proceed; log `[STARTUP#] DECISION  <topic>: <choice> (council-lite)`. Never funnel a non-gate decision to the user.

## 4. Escalation gates (the ONLY things that tap the user)

Pause autopilot and escalate ONLY for:

- 🔴 **BREAKING** — a specialist twice-failed; a blocker council-lite cannot resolve; or work would need a full revert.
- 💸 **MONETARY** — about to spend money: deploy to paid infra, paid API call, paid dependency install, provision/purchase — AND every presto image-generation batch (confirm with a per-batch cost estimate).
- 🔒 **SECURITY** — touching `.env`/secrets/credentials/auth, data exposure, or a `review-specialist:security` CRITICAL finding.
- 🧮 **TOKEN** — projected to cross the dispatch budget.
- ⚠️ **DESTRUCTIVE** — push/deploy/rm/force-push/drop. ALWAYS confirm (overrides `--ship`).

Escalation format:

```
🛑 [STARTUP] GATE: <BREAKING|MONETARY|SECURITY|TOKEN|DESTRUCTIVE> — autopilot paused.

What triggered it: <one line>
Context: <relevant detail + cost/risk estimate where applicable>

Options:
  A) <label> — <tradeoff>
  B) <label> — <tradeoff>

council-lite recommends: <X> (<reason>)   [if a council was convened]
STARTUP recommends:      <Y> (<reason>)

Reply to steer, or write STOP / REDIRECT: <text> to .devteam/control.
```

If the user is unreachable (stranded): write a `WAITING ON USER` slack entry + a detail file at `.devteam/state/slack-detail/<id>.md`, send PushNotification (unless `notify=false`), run `/checkpoint`, restore the prior mode, and exit cleanly. Next `/startup` or `/continue` resumes.

## 5. Interrupt & steering

- Any mid-run user message → treat as a steering command. Classify: **inject decision** (fold into the current phase) / **change direction** (update `think.md` + plan, may rewind a phase) / **stop**. Run `/checkpoint` first, then apply, then resume or halt.
- `.devteam/control` file, read at each phase boundary:
  - contains `STOP` → `/checkpoint`, restore the prior mode, halt with a status summary.
  - contains `REDIRECT: <text>` → fold `<text>` into `think.md`/plan, log it, continue.
  - Clear the file after acting.

## 6. Ship boundary (default stop)

After TEST passes + REVIEW is clean: STOP. Emit a completion report — what was built, the branch, test + review results, total dispatch count + soft token estimate, and the proposed ship action. Escalate for ship approval (DESTRUCTIVE gate). If `--ship` was given you may run the `shipper` recipe, but the actual push/deploy still confirms.

On clean completion or halt: restore the prior `.devteam/mode` value; log `[STARTUP#] DONE  <one-line>`.

## 7. Slack logging

Use `bin/slack-append.sh` (path from `.devteam/state/.plugin-path`). Your actor tag is `[STARTUP#]`. Members log under their own tags. Severity tags: `INFO | DECISION | QUESTION | FUNNEL | GATE | DESTRUCTIVE | DONE | ERROR | MODE | SUMMARY | WATCHLIST`.

## 8. Honesty caveats (state to the user when relevant)

- The token gate counts DISPATCHES, not real tokens; the token figure is a heuristic estimate, not metering, and cannot read your credit balance.
- Autopilot needs this session alive; it is not a background daemon. On a gate it exits cleanly with a notification and resumes via `/startup` or `/continue`.

## 9. Funnel rule

You run in the main thread and talk to the user directly (at the contract, at gates, and on interrupts). The "never call AskUserQuestion" rule applies to your dispatched members, not to you. Include the funnel-rule reminder in every member brief.
