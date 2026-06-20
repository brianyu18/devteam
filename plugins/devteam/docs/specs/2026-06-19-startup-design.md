# `/startup` — Autonomous Project Autopilot + UI Specialist Design

**Date:** 2026-06-19
**Status:** Approved design, ready for implementation plan
**Author:** Brian + Claude (collaborative brainstorm)

---

## 1. Goal

Add a **fully autonomous project autopilot** to devteam. The user gives a goal; the
system drives it from goal → ready-to-ship — classifying, framing, planning,
speccing, building, reviewing, and testing — **deciding for itself** at most
decision points (via the council), and **tapping the user only on a small set of
escalation gates**. The user can interrupt and steer (inject / redirect / stop) at
any time.

As part of this, UI/presentation work is folded into the workflow via the **presto**
design plugin, and a reusable **`frontend-specialist`** subagent is added so UI/frontend
work can be fanned out like any other build partition.

This is delivered as **two components** (build A first, then B which consumes it):
- **Component A** — `frontend-specialist` agent + presto integration (reusable by `/lead` and `/startup`).
- **Component B** — `startup` autopilot orchestrator.

---

## 2. Scope

**In scope:**
- `agents/frontend-specialist.md` — new UI/frontend builder subagent.
- `skills/startup/SKILL.md` + `commands/startup.md` — the autopilot.
- A one-note addition to `skills/lead/dispatch-recipes.md` (UI partitions + optional DESIGN step).
- presto added as a **soft/optional** plugin dependency.
- Manifest bump 1.3.0 → 1.4.0; CHANGELOG / README / ARCHITECTURE updates.

**Out of scope:**
- Modifying `skills/lead/SKILL.md`, the `council` skill, or any existing agent.
- Modifying the presto plugin (we consume it; we do not change it).
- Real token metering or reading the user's credit balance (not possible from a skill — see §9 caveat).
- A background daemon / true unattended execution (the CC session must stay alive — see §9 caveat).
- Recursive autopilot (a subagent launching its own autopilot). Blocked by the no-nested-dispatch constraint.

---

## 3. Load-bearing constraints (from prior devteam + presto exploration)

1. **Subagents cannot dispatch subagents** (`ARCHITECTURE.md`, "Why no lead agents"). Only a
   main-thread skill can use the Task tool or run a fan-out Workflow. → `startup` MUST be a
   main-thread skill; any presto phase that fans out MUST run at the main-thread level.
2. **presto's orchestration is main-thread.** `magic` runs phases 1–6 inline, phase 7 (AUDIT) as a
   parallel barrier, and `houdini`'s DRAFT substep fans out 3 drafters via a Workflow. None of that
   can run inside a subagent.
3. **presto's embeddable taste skills** — `emil-design-eng`, `imagen-direction`, and `impeccable`'s
   core rules — CAN be embodied by a single subagent (no fan-out). `design-taste-frontend` is a
   main-thread orchestrator; a subagent should consume its *outputs* (`DESIGN_APPROACH.md`,
   `tokens.css`, `DIALS.json`), not run it.
4. **presto image generation costs money** — `imagen`/nanogen call the paid Gemini image API
   (~5–30¢/image). `--nogen` disables it. → wired to the monetary gate (§6).

---

## 4. Component A — `frontend-specialist` agent + presto integration

### 4.1 The agent

`agents/frontend-specialist.md`:

```
---
name: frontend-specialist
description: Use when LEAD or STARTUP has a UI/frontend partition to implement. Builds
  components/pages embodying presto's taste skills (emil-design-eng, impeccable rules,
  imagen-direction) and consuming DESIGN-phase artifacts. Owns only its partition's files.
model: sonnet
tools: Read, Grep, Glob, Bash, Edit, Write
---
```

Body mirrors `builder.md` conventions, with UI specialisation:
- **Inputs (brief):** the UI partition (paths it owns); the DESIGN artifacts to consume
  (`tokens.css`, `DESIGN_APPROACH.md`, `DIALS.json` if present); the presto taste-skill file
  paths to READ for guidance (`skills/emil-design-eng/SKILL.md`, `skills/impeccable/SKILL.md`,
  `skills/imagen-direction/SKILL.md` under the presto install path); plugin path; slack template
  (actor tag `BUILDER:ui`); conventions; funnel rule.
- **What it does:** read the DESIGN artifacts + relevant taste-skill files; implement its
  partition (HTML/CSS/components/framework code) applying the embeddable taste rules (anti-slop
  typography/color/layout from impeccable, animation craft from emil-design-eng); write only files
  in its partition; one-line smoke/test if applicable; return a `complete`/`blocked`/`failed`
  packet (`phase: "BUILD"`).
- **Hard constraints:** owns only its partition's paths (never sibling files); does NOT run
  `magic`/`houdini`/`design-audit` (those fan out — main thread only); never calls AskUserQuestion
  (returns `blocked` with options + recommendation).

It is a general devteam agent: `/lead` and `/startup` both dispatch it for UI partitions.

### 4.2 dispatch-recipes.md note

Add to the BUILD composition section of `skills/lead/dispatch-recipes.md` (additive, ~3 lines):

> **UI partitions:** dispatch `frontend-specialist` (not `builder`) for partitions whose paths are
> UI/frontend. If presto is installed and the work is design-heavy, an optional main-thread DESIGN
> step (`/magic`) can run first to produce `tokens.css` + `DESIGN_APPROACH.md`, which become input
> artifacts for the `frontend-specialist` workers.

### 4.3 presto soft dependency

In `plugin.json` `requires.plugins`, add presto as optional:
```json
{ "name": "presto", "marketplace": "any", "optional": true }
```
If presto is absent: the DESIGN phase is skipped with a logged warning, and `frontend-specialist`
builds from plain conventions (no design system). startup must not hard-fail on missing presto.

---

## 5. Component B — `startup` orchestrator

### 5.1 Command surface

`/startup <goal>` flags:

| Flag | Effect |
|------|--------|
| `--budget <N>` | Max subagent dispatches this run (default **40**). |
| `--fanout <K>` | Max parallel subagents per wave (default **4**). |
| `--tier <t>` | Override classification (default: auto-classify; min `feature`). |
| `--ship` | Allow autopilot to also run SHIP (push/deploy still confirms — §6). |
| `--no-images` | Force presto `--nogen` (skip all paid image gen). |
| `--notify` / `--no-notify` | PushNotification on stranded gate (default ON). |
| `--goal-file <path>` | Read a longer goal brief from a file. |

### 5.2 Lifecycle

**Phase 0 — CONTRACT (the one guaranteed up-front gate):**
1. Bootstrap `.devteam/state/`; resolve + write `.plugin-path`; force `mode = autonomous` (this run);
   init `.devteam/state/.dispatch-count` = 0; write `.devteam/state/.startup` policy (budget, fanout,
   ship-boundary, images mode, gates).
2. Convene **`council --lite`** on the goal → a one-screen **CONTRACT**:
   refined goal, success criteria, tier + phase plan, **whether a DESIGN phase is needed** (UI
   detected from goal or council judgment), escalation gates, dispatch budget + **projected dispatch
   count**, ship boundary, top risks.
3. Present CONTRACT to user → **approve / edit / cancel**. On approve: write
   `.devteam/state/contract.md`, log `[STARTUP#] DECISION  contract approved`, engage autopilot.

**Autopilot loop (autonomous; reuses `lead` phase recipes by reference):**
Phases run in order, stopping before SHIP:

| Phase | Behaviour |
|-------|-----------|
| **THINK** | Frame the goal (from contract). Ambiguity → `council --lite`. |
| **DESIGN** *(only if UI; main thread)* | presto `/magic` (incl. optional `/houdini` cold-start + AUDIT barrier) → design system, `tokens.css`, `DESIGN_APPROACH.md`. Image gen per §6. |
| **PLAN** | Partition the work (wave-grouped). Architecture/spec decisions → `council --lite`. |
| **BUILD** | Fan-out-capped (`--fanout`) per wave. **UI partitions → `frontend-specialist`** (consuming DESIGN artifacts); others → `builder`. |
| **REVIEW** | Standard lenses (`bin/devteam-pick-lenses.sh`); if UI built and presto present, also run `/design-audit` (main thread). |
| **TEST** | Per detected layer (`bin/devteam-detect-stack.sh --tests`). |

**Decider policy (decision #3):**
- **Full `council --lite`** (5 agents) at: goal/contract framing, classification, architecture/spec
  decisions, and any genuinely *blocking* specialist packet.
- **Cheap CRITIC+EXPLORER pre-flight** (2 agents, `lead`'s existing autonomous mechanism) for small
  in-phase micro-ambiguities.

**Budget tracking (decision #2):**
- Every Task dispatch — `builder`, `frontend-specialist`, `tester`, `review-specialist`, every council
  member, every houdini drafter, every AUDIT check — increments `.devteam/state/.dispatch-count`.
- **Before each wave:** if `count + projected_wave_size > budget` → **TOKEN gate** (§6).
- A soft token estimate (`count × heuristic`, heuristic noted as approximate) is shown at each phase
  boundary and in escalations. It is NOT real metering (§9).

**Checkpointing:** auto-`/checkpoint` at each phase boundary so interrupts/crashes resume cleanly.

**Phase end — SHIP BOUNDARY (default stop):**
After TEST passes + REVIEW clean, **STOP**. Emit a completion report: what was built, branch,
test/review results, dispatch count + token estimate, and the proposed ship action. Escalate for
ship approval. `--ship` opts into running SHIP, but push/deploy still confirms (§6).

**Stranded gate / stall (lead §8 pattern):** write a `WAITING ON USER` slack entry + detail file,
send PushNotification (unless `--no-notify`), exit cleanly. Next `/startup` or `/continue` resumes
from the checkpoint + contract.

### 5.3 UI detection

A goal needs the DESIGN phase + `frontend-specialist` when it is UI/presentation work. Detection:
council-lite classifies it in the CONTRACT (primary), backed by a keyword heuristic (ui, frontend,
landing page, dashboard, web app, component, slides, presentation, design, marketing site). The
contract states the decision so the user can correct it before approving.

---

## 6. Escalation gates — the only things that tap the user

Autopilot pauses (and, if stranded, PushNotification + clean exit) ONLY on:

| Gate | Trigger (detection) |
|------|---------------------|
| 🔴 **Breaking** | a specialist twice-failed; a blocker `council --lite` cannot resolve; or work would need a full revert. |
| 💸 **Monetary** | about to spend money: deploy to paid infra, paid API call, paid dep install, provision/purchase — **and every presto image-gen batch** (confirmed with a per-batch cost estimate; user's explicit choice). |
| 🔒 **Security** | touching `.env`/secrets/credentials/auth; data exposure; or a `review-specialist:security` **CRITICAL** finding. |
| 🧮 **Token** | projected to cross the dispatch budget. |
| ⚠️ **Destructive** | push / deploy / rm / force-push / drop — devteam hard rule, **always** confirms (overrides `--ship`). |

Everything else → council-lite (or cheap pre-flight) decides → proceed silently.

**Escalation format** (reuses `lead`'s funnel, prefixed with the gate):
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

---

## 7. Interrupt & steering ("native message + control file")

- **Native:** the user may type at any time (Esc to interrupt a live turn). startup treats any
  mid-run user message as a steering command — classify as **inject decision** / **change direction**
  / **stop** → `/checkpoint` → apply → resume or halt.
- **Control file:** `.devteam/control` is read at **every phase boundary**:
  - `STOP` → checkpoint + halt with a status summary.
  - `REDIRECT: <text>` → fold `<text>` into `think.md` / plan, log it, continue.
  - The file is cleared after acting.

---

## 8. State files

| File | Purpose |
|------|---------|
| `.devteam/state/contract.md` | The approved contract — source of truth for the run. |
| `.devteam/state/.startup` | Policy flags (budget, fanout, ship-boundary, images mode, gates). |
| `.devteam/state/.dispatch-count` | Integer dispatch counter for the budget gate. |
| `.devteam/control` | User-writable steering file (`STOP` / `REDIRECT: <text>`). |
| `.devteam/state/slack.md` | Reused audit log; actor tag `[STARTUP#]` + member tags. |

Plus presto's own outputs under the project (`seeds/`, `memory/`, `outputs/<slug>/`) when DESIGN runs.

---

## 9. Honesty caveats (written into the skill, not hidden)

1. **Token gate is a proxy.** A skill cannot meter real tokens or read the credit balance. The gate
   counts *dispatches*; the token figure is a heuristic estimate and can drift.
2. **"Unattended" is bounded.** The CC session must stay alive and the model keeps iterating. On a
   gate, startup exits cleanly with a notification and resumes via `/startup` or `/continue`. It is
   not a background daemon.
3. **presto is optional.** If absent, DESIGN degrades to a warning + plain build; startup never
   hard-fails on missing presto.

---

## 10. Files touched

| File | Change |
|------|--------|
| `agents/frontend-specialist.md` | NEW |
| `skills/startup/SKILL.md` | NEW |
| `commands/startup.md` | NEW |
| `skills/lead/dispatch-recipes.md` | MODIFY — UI-partition + optional DESIGN note (additive) |
| `.claude-plugin/plugin.json` | MODIFY — +presto soft dep; version 1.3.0 → 1.4.0 |
| `../../.claude-plugin/marketplace.json` | MODIFY — advertise plugin 1.4.0 |
| `CHANGELOG.md` | 1.4.0 entry |
| `README.md` | `/startup` + `frontend-specialist` in the relevant sections |
| `ARCHITECTURE.md` | rationale: own-orchestrator factoring; UI nesting boundary |
| `docs/specs/2026-06-19-startup-design.md` | this file |

No changes to `lead/SKILL.md`, the `council` skill, or any existing agent.

---

## 11. Settled decisions (this brainstorm)

1. **Architecture:** startup is its own top-level orchestrator (sibling to `lead`), reusing lead's
   phase recipes by reference. No `lead/SKILL.md` changes.
2. **Default budget:** 40 dispatches / fan-out 4 (overridable; contract previews projected count).
3. **Decider:** tiered — full council-lite at consequential decisions, cheap CRITIC+EXPLORER at
   micro-blocks.
4. **Image gen:** ON, but **every batch hits the monetary gate** (per-batch cost estimate).
5. **frontend-specialist:** general devteam agent (usable by `/lead` and `/startup`).
6. **Design:** explicit main-thread DESIGN phase (presto `/magic`) before BUILD when UI is involved.

---

## 12. Open questions for the plan phase

- Exact token-estimate heuristic per dispatch (lean: a single documented constant, clearly labelled
  approximate — not per-agent calibration we don't have data for).
- Whether `--ship` should be allowed at all in v1, or deferred (lean: accept the flag but keep the
  push/deploy hard-confirm, so it only removes the *stop*, not the *confirm*).
- DESIGN-phase invocation detail: `/magic` vs `/houdini` entry selection (lean: `/magic`, which itself
  conditionally runs the houdini cold-start phase).
