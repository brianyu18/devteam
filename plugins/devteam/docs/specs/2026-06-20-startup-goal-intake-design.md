# `/startup` Goal-Intake (devteam 1.4.1) Design

**Date:** 2026-06-20
**Status:** Approved design, ready for implementation plan
**Author:** Brian + Claude (collaborative brainstorm)

---

## 1. Goal

Improve the dead-end in `/startup`: today, invoking it with **no goal** just asks
"what do you want to build?" and stops. Replace that with a **guided goal-intake** — a
short main-thread Q&A that co-authors a goal, with an opt-in `council --lite` deferral
for when the user can't phrase it — then writes `GOAL.md` and flows into the existing
CONTRACT phase. Turns "I don't know how to phrase it yet" into a guided start.

Ships as devteam **1.4.1** (patch — additive, backward compatible).

---

## 2. Scope

**In scope:**
- An `INTAKE` pre-step in the `startup` skill, triggered only when no goal is provided.
- A short fixed Q&A; an opt-in `council --lite` drafting deferral when the user is unsure.
- Writing the assembled goal to `./GOAL.md`.
- Updates to `commands/startup.md`, `README.md`, `CHANGELOG.md`, manifests (1.4.1), `TODOS.md`.

**Out of scope:**
- Any change to behavior when a goal IS provided (inline or `--goal-file`) — untouched.
- New agents/skills/commands — intake is a pre-step inside the existing `startup` skill.
- Replacing the CONTRACT phase's refinement — intake feeds it; it does not duplicate it.
- Re-prompting/intake for *thin but present* goals — only the truly-empty case is improved.

---

## 3. Trigger (decision 3 — empty-only)

The `/startup` command already parses args. INTAKE fires **only** when, after parsing,
there is **no goal string AND no `--goal-file`**. Any provided goal — even one word —
skips intake and flows straight to the contract, exactly as today. A provided goal is
never second-guessed.

---

## 4. INTAKE flow (new step in `skills/startup/SKILL.md`, before §1 CONTRACT)

Runs entirely in the main thread (the skill talks to the user directly).

### 4.1 Q&A (default path — 0 dispatches)
STARTUP asks a short, structured set of questions:

1. **What are you building?** (one sentence) — free text. This question carries an explicit
   escape option: **"I'm not sure — help me shape it."**
2. **Project type?** — web app / mobile app / CLI / API / library / other.
3. **Hard constraints?** (stack, must / must-not, deadline) — optional, free text.
4. **Scope of this first run?** — the whole thing / a foundational slice / a specific feature.

Choice-style questions (2, 4) may use `AskUserQuestion`; the open questions (1, 3) are asked
in prose so the user can answer naturally. Keep it to one round — do not interrogate.

### 4.2 Unsure path (opt-in council-lite deferral — ~5 dispatches)
Trigger this path if the user **selects "I'm not sure — help me shape it"** on Q1, OR gives
empty/too-thin answers to all questions.

STARTUP convenes **`council --lite`** (Skill tool) to **propose 1–3 candidate goal
directions**, briefed with: whatever partial answers exist + project context (cwd, `git`
state, the repo `README`, and the vault-project `CLAUDE.md` if the cwd basename matches a
vault project). The council returns candidate goals (not a verdict). STARTUP presents the
1–3 candidates; the user **picks one and edits it** (or asks for another round once).

This path costs ~5 dispatches — added to `.devteam/state/.dispatch-count` and logged. It is
opt-in (the user chose "I'm not sure"), so the cost is consented.

### 4.3 Assemble + write `GOAL.md` (decision 2)
From the confident answers (4.1) or the chosen/edited candidate (4.2), STARTUP composes a
goal brief in the same shape we hand-authored for OnlyPaws (intent, deliverables, scope,
out-of-scope, stack preference if given). It **writes the brief to `./GOAL.md`**, echoes it
to the user, and notes it's committed-ready.

### 4.4 Proceed
STARTUP enters the **existing CONTRACT phase (§1)** using the assembled goal — which already
runs the `council --lite` refinement + the user's one approval. Intake does NOT refine; it
only captures raw intent. Downstream phases are unchanged.

### 4.5 Hard fallback
If the user declines to answer even the unsure path (fully empty), STARTUP asks once more,
then exits cleanly with a one-line "give me a goal or a `--goal-file` to start" — never loops.

---

## 5. Budget interaction

- Confident Q&A path: **0 intake dispatches**. Contract's council-lite (~5) runs after, as today.
- Unsure path: **~5 intake dispatches** + contract's ~5 = ~10 before BUILD — still comfortable
  within the default 40 budget. The pre-wave TOKEN-gate check (§2 of the skill) still applies.

The token-estimate caveat is unchanged: dispatch count is a proxy, not real metering.

---

## 6. Files touched

| File | Change |
|------|--------|
| `skills/startup/SKILL.md` | NEW §0.5 INTAKE step (4.1–4.5); §1 CONTRACT now "uses the goal (provided OR from intake)" |
| `commands/startup.md` | Empty-goal branch: instead of "ask what to build and stop", hand control to the skill's INTAKE step |
| `README.md` | "Bare `/startup`" bullet: drop the "Planned 1.4.1" note; describe intake + the unsure→council-lite deferral |
| `.claude-plugin/plugin.json` | version 1.4.0 → 1.4.1 |
| `../../.claude-plugin/marketplace.json` | advertise plugin 1.4.1 |
| `CHANGELOG.md` | 1.4.1 entry |
| `TODOS.md` | tick the 1.4.1 goal-intake item (move out of Tier 1 backlog) |
| `docs/specs/2026-06-20-startup-goal-intake-design.md` | this file |

No new agents, skills, commands, or state files. No change when a goal is provided.

---

## 7. Settled decisions

1. **Intake mechanism:** fixed main-thread Q&A by default (0 dispatches), with an **opt-in
   `council --lite` deferral** when the user selects "I'm not sure" or answers too thin.
2. **Output:** write the assembled goal to `./GOAL.md` (committed-ready, reusable, survives
   `/continue`).
3. **Trigger:** empty-only — never intercepts a provided goal.

---

## 8. Open questions for the plan phase

- Exact phrasing of the 4 intake questions (lean: as drafted in §4.1).
- Whether the council-lite "propose candidate goals" brief needs a dedicated note vs. reusing
  the council skill's existing brief shape (lean: reuse; pass a "propose 1–3 goal directions,
  don't verdict" synthesis goal).
- Whether to `git add`/commit `GOAL.md` automatically or just write it (lean: write only; let
  the BUILD/SHIP phases commit it with the rest, so intake stays side-effect-light).
