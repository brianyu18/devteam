# `/council` — Devteam Deliberation Council Design

**Date:** 2026-06-13
**Status:** Approved design, ready for implementation plan
**Author:** Brian + Claude (collaborative brainstorm)

---

## 1. Goal

Add a **council** capability to devteam: an on-demand panel of existing devteam
specialists that the user can convene at any time to pressure-test a question,
decision point, or proposal — and return a single *reasoned result* to the lead.

Unlike the LEAD phase pipeline (THINK→…→REFLECT, which *builds software*), the
council *deliberates*. It refines the question, gathers neutral evidence, runs a
structured pro/con debate, scrutinises the proposal for fallacies, optionally
surfaces unconsidered options, and synthesises a verdict with preserved dissent.

The council does not implement anything. Its only output is a reasoned answer.

---

## 2. Scope

**In scope (this design):**
- `skills/council/SKILL.md` — orchestrator skill (runs in main thread = the lead)
- `commands/council.md` — `/council <question>` entry point + flag parsing
- `agents/reasoning-reviewer.md` — one new read-only agent (abstract-mode reviewer)
- Manifest bump 1.2.0 → 1.3.0; marketplace advertise 1.3.0
- Docs: CHANGELOG, README (skill comparison), ARCHITECTURE (rationale)

**Out of scope:**
- New advocacy/evidence agents — the council *reuses* `investigator`, `explorer`,
  `critic`, `review-specialist`, `synthesizer` unchanged.
- Persisting council verdicts to long-term memory (`~/.claude/devteam/memory/`).
  Council is ephemeral by default; memory elevation is a future option.
- Nested/recursive councils (a council member convening its own council). Blocked
  by the Claude Code constraint that subagents cannot dispatch subagents.

---

## 3. Why a skill, not an agent (load-bearing constraint)

Per `ARCHITECTURE.md` ("Why no lead agents"): **subagents in Claude Code cannot
dispatch nested subagents.** A Task-tool agent runs in a fresh context without the
Task tool. Only code running in the *main thread as a skill* can dispatch via Task.

Therefore the council orchestrator MUST be a skill (like `lead`), running in the
main thread, dispatching all members itself. This mirrors LEAD's proven model.

---

## 4. Roster — mapping the ask onto real agents

The user's role names do not map 1:1 onto devteam's agent taxonomy. The approved
mapping is honest to what each agent's system prompt is actually built to do
(evidence: agent `.md` files read during brainstorm):

| User's term            | Realised as                    | Why |
|------------------------|--------------------------------|-----|
| 2 "pro" critics        | 2× `explorer` ("argue FOR")    | `explorer.md`: "construct the strongest possible case for your assigned angle." It is the advocate for *any* angle. |
| 2 "con" critics        | 2× `critic`                    | `critic.md`: "Do not try to be balanced or supportive… find the weaknesses." Con-only by design. |
| 2 investigators        | 2× `investigator` (**neutral**)| `investigator.md`: "you read and report." Its value is a shared, *unbiased* evidence base both sides cite. Never assigned a side. |
| 2 reviewers            | adaptive (see §5)              | Review the *proposal's quality*, not the substance. |
| optional 1 explorer    | 1× `explorer` ("divergent")    | The user's "explore new options" intuition — same agent, a *reframing* brief instead of an advocacy brief. |
| optional 1 synthesizer | 1× `synthesizer` (**mandatory**)| Promoted to mandatory: it produces the "reasoned result returned to the lead," which is the council's whole purpose. |

Layered view:

| Layer      | Members                                   | Function |
|------------|-------------------------------------------|----------|
| Evidence   | 2× investigator (neutral)                 | Establish shared facts |
| Advocacy   | 2× explorer (pro) + 2× critic (con)       | The debate |
| Scrutiny   | 2× reviewer + optional 1× explorer (div.) | Critique proposal quality; surface new options |
| Verdict    | 1× synthesizer (mandatory)                | Merge into reasoned answer + dissent |

Baseline = **9 agents** (2+2+2+2+1). With the divergent explorer = **10**.

---

## 5. Adaptive reviewers (code-mode vs abstract-mode)

The council adapts the 2 "reviewer" seats to the subject matter (user chose
"Both, council adapts"):

- **Code-mode** — a git diff or named code artifact is present (or `--diff <ref>`
  forced). The 2 reviewers run as `review-specialist` instances over lenses
  selected by `bin/devteam-pick-lenses.sh`, exactly as in the LEAD REVIEW phase.
- **Abstract-mode** — the subject is a question/decision/proposal with no diff.
  `review-specialist` cannot run (it is hardwired to `git diff` a lens). The 2
  reviewers run as the **new `reasoning-reviewer`** agent: a read-only critic of
  *reasoning* — logical fallacies, unstated assumptions, evidence gaps, internal
  inconsistency, scope creep. This directly serves the user's "question fallacies"
  requirement.

Mode detection (INTAKE step): if `--diff` given → code-mode; else if `git diff
--quiet` shows uncommitted changes OR the question references a code artifact →
code-mode; else → abstract-mode. The lead states the detected mode at convene time.

---

## 6. New agent: `reasoning-reviewer`

```
---
name: reasoning-reviewer
description: Use when the council needs a non-code proposal/argument reviewed for
  logical fallacies, unstated assumptions, evidence gaps, and internal
  inconsistency. Read-only. Returns findings, not a verdict.
model: sonnet
tools: Read, Grep, Glob, Bash
---
```

Contract mirrors `critic`/`review-specialist` conventions:
- **Inputs (brief):** the proposition + the question being decided; the evidence
  artifacts (investigator outputs); plugin install path; `slack-append.sh`
  template with actor tag `REVIEWER`; the funnel rule.
- **What it does:** read the proposition and evidence; scan for fallacy classes
  (appeal-to-X, false dilemma, hasty generalisation, circularity, equivocation,
  survivorship, base-rate neglect…), unstated assumptions, claims unsupported by
  the evidence base, and internal contradictions. Rate each finding
  CRITICAL/MAJOR/MINOR + confidence 0–100.
- **Returns:** a `complete` packet; `notes_for_lead` carries a structured findings
  list (same shape family as `critic`'s risk list).
- **Hard constraints:** read-only (no source edits); never call AskUserQuestion
  (return `blocked` with options only if it cannot review at all).

It is reusable outside the council (any abstract-reasoning review), so it lives in
`agents/`, not embedded in the skill.

---

## 7. Orchestration flow (the skill body)

```
INTAKE  (lead, main thread)
  1. Parse the proposition. Restate it crisply; surface hidden assumptions.
  2. Detect mode (code vs abstract) per §5; announce it.
  3. Decide divergent-explorer inclusion: include for open-ended "what should
     we do" questions; skip for binary yes/no. Honour --lite.
  4. Bootstrap plugin path: read .devteam/state/.plugin-path if present, else
     use ${CLAUDE_PLUGIN_ROOT} (passed by the command). If state/ exists, open a
     [COUNCIL#] slack INFO line.

WAVE 1 — Evidence  (one Task message, 2 parallel blocks)
  - 2× investigator, distinct scopes (e.g. "facts supporting feasibility/context"
    vs "facts about risks/constraints/precedent"). Neutral briefs.
  - Collect both packets; these become input artifacts for Wave 2.

WAVE 2 — Advocacy + Scrutiny  (one Task message, parallel blocks)
  - 2× explorer  "argue FOR" — two distinct pro angles
  - 2× critic    "argue AGAINST / reasons not to proceed"
  - 2× reviewer  review-specialist (code-mode) | reasoning-reviewer (abstract-mode)
  - 1× explorer  "divergent: surface options nobody proposed"  [optional]
  All fed the Wave-1 evidence as input artifacts.

WAVE 3 — Verdict  (single Task)
  - 1× synthesizer (mandatory), fed ALL Wave-1 + Wave-2 outputs. Synthesis goal:
    produce the §8 verdict structure — refined question, verdict + confidence,
    strongest FOR/AGAINST, evidence base, fallacies flagged, options surfaced,
    dissent worth keeping, recommended next step.

DELIVERY (lead)
  - Relay the synthesizer's verdict. If the lead's own read diverges from the
    synthesizer, append a one-line lead take (the existing two-recommendation
    funnel pattern). If state/ exists: write state/council.md + [COUNCIL#] DONE.
```

Failure handling mirrors LEAD: a failed member is retried once with a "previous
attempt failed because X" addendum; on second failure the council proceeds with a
noted gap rather than blocking (a missing single voice should not sink the panel).

---

## 8. Verdict return format

```
## ⚖️ Council Verdict — <sharpened question>

Refined question:      <proposition sharpened, assumptions surfaced>
Verdict:               <recommendation>   (confidence: High | Medium | Low)
Strongest FOR:         <best pro case, citing evidence>
Strongest AGAINST:     <best con case, citing evidence>
Evidence base:         <what investigators established>
Fallacies / weaknesses: <from reviewers>
Unconsidered options:  <from divergent explorer, if it ran; else "—">
Dissent worth keeping: <minority view the lead should not discard>
Recommended next step:  <action>
```

---

## 9. Command surface

`/council <question>` — flags follow `lead` conventions:

| Flag             | Effect |
|------------------|--------|
| `--lite`         | Trim to 1 investigator + 1 pro + 1 con + 1 reviewer + synthesizer (5 agents). |
| `--model <m>`    | Override all members (`sonnet\|opus\|haiku`), same cascade as `/lead` §5.5. |
| `--diff <ref>`   | Force code-mode against a git range. |
| `--no-divergent` | Skip the optional divergent explorer even for open-ended questions. |

Defaults:
- **Ephemeral by default.** No `.devteam/state/` required — runnable from any repo
  or none. If `state/` exists, also log slack + write `state/council.md`.
- Member models = per-agent frontmatter defaults, **except** synthesizer is
  upgraded to `sonnet` in council context (it writes the capstone verdict), unless
  `--model` overrides everything.
- `${CLAUDE_PLUGIN_ROOT}` is captured by the command and passed to the skill so
  member briefs can reference `bin/` and `agents/review-lenses/` without state.

Slack actor tags (only when state/ exists): `[COUNCIL#]` (lead),
`[INVESTIGATOR#]`, `[EXPLORER#]`, `[CRITIC#]`, `[REVIEW:<lens>#]` /
`[REVIEWER#]`, `[SYNTHESIZER#]`.

---

## 10. Files touched

| File | Change |
|------|--------|
| `skills/council/SKILL.md` | NEW — orchestrator skill |
| `commands/council.md` | NEW — `/council` command |
| `agents/reasoning-reviewer.md` | NEW — abstract-mode reviewer |
| `.claude-plugin/plugin.json` | version 1.2.0 → 1.3.0 |
| `../../.claude-plugin/marketplace.json` | advertise plugin 1.3.0 |
| `CHANGELOG.md` | 1.3.0 entry |
| `README.md` | council in skill-comparison section |
| `ARCHITECTURE.md` | "Why the council is a skill" + roster-mapping rationale |
| `docs/specs/2026-06-13-council-design.md` | this file |

Backward compatible: no existing agent, skill, command, or state file is modified.

---

## 11. Open questions for the plan phase

- Exact pro/con angle phrasing the lead generates per question (templated vs
  freeform). Lean: short freeform angles derived from the proposition.
- Whether `--lite` keeps the divergent explorer (current design: no).
- Whether to add a `bin/` helper for mode detection or inline it in the skill
  (lean: inline — it is a two-line git check).
