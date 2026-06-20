# LEAD Dispatch Recipes

Per-tier phase subsets and brief composition rules.

## Tier: simple
**Phases:** BUILD (lite) + TEST (verify only).
- Skip plan partitioning — single BUILDER.
- BUILDER brief: "Make the change. Read the file and direct dependencies. One-line test if applicable."
- TESTER brief: "Run existing suite, report pass/fail."
- No REVIEW, no REFLECT.

## Tier: bug
**Phases:** THINK (lite) + BUILD + TEST + REVIEW.
- THINK lite: "Frame the bug. Symptom? Suspected root cause? Minimal repro?"
- BUILDER: write a failing test capturing the bug FIRST (red), then fix until green.
- REVIEW: focus on root cause vs symptom.
- REFLECT: focused — root cause + prevention.

## Tier: feature
**Phases:** THINK + PLAN + BUILD + REVIEW + TEST + SHIP.
- Full PLAN with wave-grouped partitions in `state/plan-partitions.md`.
- BUILD fans out per wave when partitions are `parallel_safe: true`.
- REVIEW: lens list from `bin/devteam-pick-lenses.sh`; one `review-specialist` worker per lens, dispatched in parallel.
- TEST: layer list from `bin/devteam-detect-stack.sh --tests`; one `tester` per layer, dispatched in parallel.
- SHIP: standard project-type detection.
- REFLECT: light (3 bullets).

## Tier: complex
**Phases:** All 7 with full retro.
- THINK may use shotgun mode (3× explorer) and read `DESIGN.md` if present.
- PLAN includes parallel critique fan-out via gstack /plan-*-review (or self-fanout in autonomous).
- BUILD fans out per partition wave.
- REVIEW: maximize lens coverage; include `/codex` consult if gstack installed.
- TEST: every detected layer.
- SHIP: full sequence; chain `gstack:/document-release` after merge.
- REFLECT: full retro; include WATCHLIST analyzer output.

## UI partitions

For partitions whose `paths` are UI/frontend (components, pages, styles, design system):

- Dispatch `frontend-specialist` (not `builder`). Its brief additionally includes the DESIGN-phase artifact paths (`tokens.css`, `DESIGN_APPROACH.md`, `DIALS.json` if present) and the presto taste-skill paths to read (`skills/{emil-design-eng,impeccable,imagen-direction}/SKILL.md` under the presto install path).
- If presto is installed and the work is design-heavy, an optional main-thread DESIGN step (`/magic`) can run before BUILD to produce those artifacts. The DESIGN step runs in the main thread (it fans out / generates images); a `frontend-specialist` subagent must never invoke `/magic`, `/houdini`, or `/design-audit`.
- Image generation (presto nanogen → paid Gemini API) is a main-thread, monetary-gated action; workers do not call it.

## Brief composition (every dispatch)

LEAD includes in every worker brief:

1. Role + current phase + tier.
2. Absolute plugin install path (read `.devteam/state/.plugin-path`; expand `${CLAUDE_PLUGIN_ROOT}` at brief time).
3. `bin/slack-append.sh` command template, with the worker's actor tag (`[BUILDER:fe#]` etc.).
4. Input artifacts (file paths to read).
5. Output contract (which files to write, which slack severity tags to log under).
6. Question-packet schema reminder (`docs/question-packet-schema.json` + `docs/question-packet.md`).
7. Funnel rule reminder: "Don't call AskUserQuestion. Return a `blocked` packet with options + your recommendation."
8. **Resolved model** — pass via Task tool's `model` parameter, NOT the brief text. Compute via the cascade in `skills/lead/SKILL.md` §5.5: `--model` flag (from `.devteam/state/.flags`) → lens-spec frontmatter `model:` (review-specialist only) → agent frontmatter `model:` default → inherit. Workers don't choose their own model.

## Model selection cascade

```
┌─ LEAD invocation ─────────────────────────────────────┐
│                                                        │
│  /lead --model <name>     →  .devteam/state/.flags    │
│                              "model=<name>"            │
│                                                        │
└─────────────┬──────────────────────────────────────────┘
              │
              ▼
┌─ At each Task-tool dispatch ──────────────────────────┐
│                                                        │
│  1. .flags has model=<X>?              → use X         │
│  2. else, dispatching review-specialist                │
│     and lens spec has model: <X>?      → use X         │
│  3. else, agent frontmatter model: X?  → use X         │
│  4. else                               → omit (inherit)│
│                                                        │
│  Pass result as Task tool's `model` parameter.         │
│                                                        │
└────────────────────────────────────────────────────────┘
```

Defaults summary (per-agent frontmatter today):

| Agent | model |
|---|---|
| `builder` | `sonnet` |
| `frontend-specialist` | `sonnet` |
| `review-specialist` | `sonnet` (lens spec may override) |
| `tester` | `haiku` |
| `explorer` | `sonnet` |
| `critic` | `sonnet` |
| `synthesizer` | `haiku` |
| `investigator` | `sonnet` |

Lens overrides (per-lens frontmatter):

| Lens | model |
|---|---|
| `data-migration` | `opus` (high stakes; always upgrade) |
| `security` | `sonnet` |
| `perf` | `sonnet` |
| `api-contract` | `sonnet` |
| `testing` | `haiku` |
| `a11y` | `haiku` |

## Per-actor counter management

Each actor maintains its own counter via `bin/slack-append.sh`'s automatic substitution: pass `[ACTOR#]` as a placeholder; the script writes `[ACTOR#NN]` with the next per-actor counter value. LEAD does not centrally allocate. Counter files live at `.devteam/state/.counters/<actor>`.

Naming convention for fan-out workers: `BUILDER:<partition-id>` (e.g., `BUILDER:fe`, `BUILDER:api`), `REVIEW:<lens>` (e.g., `REVIEW:security`), `TESTER:<layer>` (e.g., `TESTER:vitest`). Each gets its own counter.
