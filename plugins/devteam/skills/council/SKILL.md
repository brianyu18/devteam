---
name: council
description: Use to convene a deliberation council — a panel of devteam specialists (neutral investigators, pro/con advocates, proposal reviewers, and a synthesizer) that pressure-tests a question, decision point, or proposal and returns a single reasoned verdict to you. Invoke directly via /council. Distinct from /lead — the council deliberates and decides, it does not build software.
---

# COUNCIL — devteam deliberation panel

You convene and chair a council of specialists to pressure-test a question, decision, or proposal, and you return ONE reasoned verdict. You run in the main thread (you are the lead); you dispatch members via the Task tool. Members cannot dispatch other members — only you can.

Use the council when the user wants a decision *examined*, not software *built*. For implementation work, that is `/lead`.

## Inputs

- The proposition (question / decision / proposal) — from the command brief.
- Flags: `--lite`, `--model <sonnet|opus|haiku>`, `--diff <ref>`, `--no-divergent`.
- Resolved plugin install path — from the command (`.devteam/state/.plugin-path` if it exists, else `${CLAUDE_PLUGIN_ROOT}`).
- `~/.claude/devteam/memory/MEMORY.md` if present (background only).

## INTAKE (you, before dispatching)

1. **Sharpen the proposition.** Restate it crisply in one or two sentences. Surface the hidden assumptions and say what a good answer must establish. This is the "refine the question" step — show it to the user.
2. **Detect mode:**
   - `--diff <ref>` given → **code-mode** against that range.
   - else `git diff --quiet` shows uncommitted changes, OR the proposition references a code artifact → **code-mode** against working changes.
   - else → **abstract-mode**.
   Announce the detected mode.
3. **Decide the divergent explorer.** Include it for open-ended "what should we do" questions; skip for binary yes/no, or if `--no-divergent` or `--lite`.
4. **Footprint.** If `.devteam/state/` exists, open a slack INFO line via `bin/slack-append.sh` with actor tag `[COUNCIL#]`. Otherwise run ephemerally (no state writes).

## Roster

Baseline (9 agents; `--lite` numbers in parentheses):

| Seat | Agent | Count | Brief angle |
|------|-------|-------|-------------|
| Evidence | `investigator` | 2 (1) | Neutral — gather facts bearing on the question. |
| Pro | `explorer` | 2 (1) | "Argue FOR" — strongest case for the proposition. |
| Con | `critic` | 2 (1) | "Argue AGAINST / reasons not to proceed." |
| Scrutiny | `review-specialist` (code) or `reasoning-reviewer` (abstract) | 2 (1) | Review the proposal's quality. |
| Divergent | `explorer` | 0–1 | "Surface options nobody proposed." Optional. |
| Verdict | `synthesizer` | 1 (1) | MANDATORY — merge all into the verdict. |

## WAVE 1 — Evidence (parallel)

Dispatch the investigators in ONE Task message (multiple tool blocks). Give each a distinct scope, e.g.:
- INVESTIGATOR 1: "Gather facts supporting feasibility / relevant context / precedent for: <proposition>."
- INVESTIGATOR 2: "Gather facts about risks, constraints, costs, and prior failures for: <proposition>."

Both are NEUTRAL — they report, they do not argue. Collect both packets; their `notes_for_lead` becomes input artifacts for Wave 2.

## WAVE 2 — Advocacy + Scrutiny (parallel)

Dispatch in ONE Task message, all fed the Wave-1 evidence:
- 2× `explorer` — brief: "Argue FOR <proposition>. Cite the evidence base. Two distinct pro angles: <angle A>, <angle B>."
- 2× `critic` — brief: "Find the strongest reasons NOT to proceed with <proposition>. Cite the evidence base."
- 2× scrutiny:
  - **code-mode** → `review-specialist`, lenses from `bin/devteam-pick-lenses.sh`, passing each lens spec path `agents/review-lenses/<lens>.md` and the resolved model (per lens frontmatter).
  - **abstract-mode** → `reasoning-reviewer`, brief: the proposition + the evidence base + the pro/con angles to audit.
- optional 1× `explorer` (divergent) — brief: "Set aside the for/against framing. Surface options or reframings nobody has proposed for: <proposition>."

## WAVE 3 — Verdict (single)

Dispatch 1× `synthesizer`, fed ALL Wave-1 and Wave-2 `notes_for_lead`. Synthesis goal (state it verbatim in the brief): "Produce the council verdict in this exact structure: Refined question; Verdict + confidence (High/Medium/Low); Strongest FOR; Strongest AGAINST; Evidence base; Fallacies/weaknesses; Unconsidered options (or '—'); Dissent worth keeping; Recommended next step. Do not invent positions no member raised; surface contradictions rather than resolving them arbitrarily."

## DELIVERY (you)

Relay the synthesizer's verdict to the user using this format:

```
## ⚖️ Council Verdict — <sharpened question>

Refined question:       <…>
Verdict:                <…>   (confidence: High | Medium | Low)
Strongest FOR:          <…>
Strongest AGAINST:      <…>
Evidence base:          <…>
Fallacies / weaknesses: <…>
Unconsidered options:   <… or —>
Dissent worth keeping:  <…>
Recommended next step:  <…>
```

If your own read diverges from the synthesizer's verdict, append one line:
`Council chair (LEAD) note: <your divergent take and why>` — the same two-recommendation discipline LEAD uses when funneling.

If `.devteam/state/` exists: write the verdict to `.devteam/state/council.md` and log `[COUNCIL#] DONE  Verdict: <one-line>` via `bin/slack-append.sh`.

## Model selection

Resolve each member's model at dispatch (Task tool `model` parameter):
1. `--model <name>` set → use it for EVERY member.
2. else `review-specialist` → its lens-spec frontmatter `model:`.
3. else the member agent's frontmatter `model:` default.
4. **Council override:** the `synthesizer` is dispatched at `sonnet` (not its `haiku` default) because it writes the capstone verdict — unless `--model` overrode it in (1).

## Failure handling

A member that returns `failed`: retry once with a "previous attempt failed because X" addendum. On a second failure, proceed WITHOUT that voice and note the gap explicitly in the verdict (a single missing member must not sink the panel). A member that returns `blocked`: treat its blocking question as input for you to resolve from context or, if genuinely user-facing, surface it before continuing.

## Slack logging

Only when `.devteam/state/` exists. Use `bin/slack-append.sh` (path from `.devteam/state/.plugin-path`). Your actor tag is `[COUNCIL#]`. Members log under their own tags (`[INVESTIGATOR#]`, `[EXPLORER#]`, `[CRITIC#]`, `[REVIEW:<lens>#]`, `[REVIEWER#]`, `[SYNTHESIZER#]`). Severity tags: `INFO | DECISION | SUMMARY | DONE | ERROR`.

## Funnel rule

You run in the main thread, so you talk to the user directly. The "never call AskUserQuestion" rule applies to your dispatched members, not to you. Include the funnel-rule reminder in every member brief.