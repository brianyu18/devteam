# Startup Goal-Intake (1.4.1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace bare `/startup`'s "ask + stop" dead-end with a guided goal-intake — a short Q&A (with an opt-in `council --lite` deferral when unsure) that co-authors a goal, writes `GOAL.md`, and flows into the existing CONTRACT phase.

**Architecture:** Additive pre-step inside the existing `startup` skill; fires only when no goal is provided. No new agents/skills/commands. Backward compatible (provided goals untouched). Patch release 1.4.0 → 1.4.1.

**Tech Stack:** Markdown prompt artifacts + JSON manifests. Verification = artifact validity + cross-reference + anchor checks (no code runtime).

**Spec:** `docs/specs/2026-06-20-startup-goal-intake-design.md`

**Repo root:** `/Users/brian/.claude/plugins/marketplaces/devteam`
**Plugin dir (`$PD`):** `<repo>/plugins/devteam`

---

## File Structure

| File | Change |
|------|--------|
| `$PD/skills/startup/SKILL.md` | Insert `## 0.5 INTAKE` between Boot (§0) and CONTRACT (§1); note §1 uses the goal "provided OR assembled in §0.5". |
| `$PD/commands/startup.md` | Empty-goal branch: hand to the skill's INTAKE instead of "ask + stop". |
| `$PD/README.md` | Rewrite the "Bare `/startup`" bullet (drop the "Planned 1.4.1" note). |
| `$PD/.claude-plugin/plugin.json` | 1.4.0 → 1.4.1. |
| `.claude-plugin/marketplace.json` (repo root) | advertise 1.4.1. |
| `$PD/CHANGELOG.md` | 1.4.1 entry. |
| `$PD/TODOS.md` | tick the 1.4.1 goal-intake item. |

> **Branching (executor, before Task 1):** `git -C /Users/brian/.claude/plugins/marketplaces/devteam checkout -b feat/startup-goal-intake`. Do not commit to `main`. Commit the spec + this plan as the foundation:
> ```
> cd /Users/brian/.claude/plugins/marketplaces/devteam
> git add plugins/devteam/docs/specs/2026-06-20-startup-goal-intake-design.md plugins/devteam/docs/plans/2026-06-20-startup-goal-intake.md
> git commit -m "docs(devteam): startup goal-intake (1.4.1) spec + plan"
> ```

---

### Task 1: INTAKE step in the startup skill

**Files:**
- Modify: `$PD/skills/startup/SKILL.md`

- [ ] **Step 1: Read the Boot→CONTRACT boundary to confirm anchors**

Run:
```bash
PD=/Users/brian/.claude/plugins/marketplaces/devteam/plugins/devteam
grep -n '^## 0. Boot\|^## 1. CONTRACT phase\|if absent, the DESIGN phase will be skipped' $PD/skills/startup/SKILL.md
```
Expected: the `## 0. Boot` heading, the Boot section's last line ("…if absent, the DESIGN phase will be skipped with a warning."), and the `## 1. CONTRACT phase (the one guaranteed up-front gate)` heading. Read the file so the edits below match exactly.

- [ ] **Step 2: Insert the INTAKE section immediately BEFORE the `## 1. CONTRACT phase` line**

Insert this block (verbatim), with a blank line after it, directly above `## 1. CONTRACT phase (the one guaranteed up-front gate)`:

```markdown
## 0.5 INTAKE (only when no goal was provided)

If the command handed you **no goal string AND no `--goal-file`**, do NOT stop — run goal-intake to co-author one. (If a goal WAS provided, skip this entire section and go to §1.)

### Q&A (default — 0 dispatches)
Ask the user in ONE short round (use `AskUserQuestion` for the choice questions, prose for the open ones — do not interrogate):

1. **What are you building?** (one sentence). Offer an explicit escape option: **"I'm not sure — help me shape it."**
2. **Project type?** — web app / mobile app / CLI / API / library / other.
3. **Hard constraints?** (stack, must / must-not, deadline) — optional.
4. **Scope of this first run?** — the whole thing / a foundational slice / a specific feature.

### Unsure → council-lite deferral (opt-in, ~5 dispatches)
If the user picks **"I'm not sure — help me shape it"** on Q1, OR gives empty/too-thin answers, convene `council --lite` (Skill tool) to **propose 1–3 candidate goal directions** — synthesis goal stated verbatim: "Propose 1–3 concrete goal directions for this project; do NOT verdict." Brief it with the partial answers + project context: cwd, `git` state, the repo `README`, and the vault-project `CLAUDE.md` if the cwd basename matches a vault project. Add the dispatches to `.devteam/state/.dispatch-count`. Present the candidates; the user picks one and edits it (allow one more round if asked).

### Assemble + write GOAL.md
Compose the confident answers (or the chosen candidate) into a goal brief — intent, deliverables, scope, out-of-scope, stack preference if given (the same shape as any `--goal-file`). Write it to `./GOAL.md`, echo it to the user, and note it is committed-ready. Do NOT `git commit` it here — BUILD/SHIP commit it with the rest; INTAKE stays side-effect-light. Use this goal for §1.

### Hard fallback
If the user declines even the unsure path (fully empty), ask once more; if still nothing, exit cleanly: "Give me a goal or a `--goal-file` to start." Never loop.

```

- [ ] **Step 3: Note the goal source in §1**

In `## 1. CONTRACT phase`, change the first numbered step's opening so it reads from either source. Find:
```
1. Convene `council --lite` (Skill tool) on the goal. Brief it to produce a CONTRACT covering:
```
Replace with:
```
1. Convene `council --lite` (Skill tool) on the goal (provided by the command, or assembled in §0.5 INTAKE). Brief it to produce a CONTRACT covering:
```

- [ ] **Step 4: Validate the section landed in order**

Run:
```bash
PD=/Users/brian/.claude/plugins/marketplaces/devteam/plugins/devteam
grep -n '^## 0. Boot\|^## 0.5 INTAKE\|^## 1. CONTRACT phase' $PD/skills/startup/SKILL.md
grep -c 'I.m not sure — help me shape it' $PD/skills/startup/SKILL.md
grep -c 'assembled in §0.5 INTAKE' $PD/skills/startup/SKILL.md
```
Expected: line order Boot < 0.5 INTAKE < 1. CONTRACT; the escape phrase count ≥ 1 (it appears in Q&A and the unsure trigger); the §1 note count = 1.

- [ ] **Step 5: Commit**

```bash
cd /Users/brian/.claude/plugins/marketplaces/devteam
git add plugins/devteam/skills/startup/SKILL.md
git commit -m "feat(devteam): startup INTAKE step — guided goal-intake for bare /startup"
```

---

### Task 2: Command empty-goal branch → intake

**Files:**
- Modify: `$PD/commands/startup.md`

- [ ] **Step 1: Read the current empty-goal line**

Run: `grep -n 'empty and no .--goal-file\|ask the user what to build' /Users/brian/.claude/plugins/marketplaces/devteam/plugins/devteam/commands/startup.md`
Expected: the line "Everything not a flag is the goal. If the goal is empty and no `--goal-file` is given, ask the user what to build and stop." Read the file.

- [ ] **Step 2: Replace the empty-goal behavior**

Find:
```
   - Everything not a flag is the goal. If the goal is empty and no `--goal-file` is given, ask the user what to build and stop.
```
Replace with:
```
   - Everything not a flag is the goal. If the goal is empty and no `--goal-file` is given, do NOT stop — the `startup` skill runs its §0.5 INTAKE step to co-author a goal (short Q&A, with an opt-in `council --lite` deferral when unsure) and write `GOAL.md`.
```

- [ ] **Step 3: Validate**

Run:
```bash
PD=/Users/brian/.claude/plugins/marketplaces/devteam/plugins/devteam
grep -c 'INTAKE step to co-author' $PD/commands/startup.md
grep -c 'ask the user what to build and stop' $PD/commands/startup.md
```
Expected: `1` and `0` (old text gone).

- [ ] **Step 4: Commit**

```bash
cd /Users/brian/.claude/plugins/marketplaces/devteam
git add plugins/devteam/commands/startup.md
git commit -m "feat(devteam): /startup empty-goal branch hands to INTAKE"
```

---

### Task 3: README "Bare /startup" bullet

**Files:**
- Modify: `$PD/README.md`

- [ ] **Step 1: Find the bullet**

Run: `grep -n 'Bare ./startup' /Users/brian/.claude/plugins/marketplaces/devteam/plugins/devteam/README.md`
Expected: the line "3. **Bare `/startup`:** prompts for what to build. *(Planned 1.4.1: a guided goal-intake that drafts the goal for you here.)*". Read the surrounding list.

- [ ] **Step 2: Replace the bullet**

Find:
```
3. **Bare `/startup`:** prompts for what to build. *(Planned 1.4.1: a guided goal-intake that drafts the goal for you here.)*
```
Replace with:
```
3. **Bare `/startup`:** runs a guided **goal-intake** — a short Q&A (with an "I'm not sure → `council --lite` proposes options" escape) that co-authors the goal, writes it to `GOAL.md`, then proceeds into the contract. (1.4.1+)
```

- [ ] **Step 3: Validate**

Run:
```bash
PD=/Users/brian/.claude/plugins/marketplaces/devteam/plugins/devteam
grep -c 'guided \*\*goal-intake\*\*' $PD/README.md
grep -c 'Planned 1.4.1' $PD/README.md
```
Expected: `1` and `0` (the "Planned" note removed).

- [ ] **Step 4: Commit**

```bash
cd /Users/brian/.claude/plugins/marketplaces/devteam
git add plugins/devteam/README.md
git commit -m "docs(devteam): README — bare /startup now runs goal-intake"
```

---

### Task 4: Version bump 1.4.0 → 1.4.1

**Files:**
- Modify: `$PD/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (repo root)

- [ ] **Step 1: Confirm current (1.4.0)**

Run:
```bash
R=/Users/brian/.claude/plugins/marketplaces/devteam
jq -r .version $R/plugins/devteam/.claude-plugin/plugin.json
jq -r '.plugins[0].version' $R/.claude-plugin/marketplace.json
```
Expected: `1.4.0` / `1.4.0`.

- [ ] **Step 2: Bump `plugin.json`** — change `"version": "1.4.0",` to `"version": "1.4.1",`.

- [ ] **Step 3: Bump `marketplace.json`** — in `plugins[0]`, change `"version": "1.4.0",` to `"version": "1.4.1",`. Leave `metadata.version` (`1.0.1`) unchanged.

- [ ] **Step 4: Validate (green)**

Run:
```bash
R=/Users/brian/.claude/plugins/marketplaces/devteam
jq empty $R/plugins/devteam/.claude-plugin/plugin.json && echo "plugin.json valid"
jq empty $R/.claude-plugin/marketplace.json && echo "marketplace.json valid"
jq -r .version $R/plugins/devteam/.claude-plugin/plugin.json
jq -r '.plugins[0].version' $R/.claude-plugin/marketplace.json
jq -r '.metadata.version' $R/.claude-plugin/marketplace.json
```
Expected: both valid, `1.4.1`, `1.4.1`, `1.0.1`.

- [ ] **Step 5: Commit**

```bash
cd /Users/brian/.claude/plugins/marketplaces/devteam
git add plugins/devteam/.claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "chore(devteam): bump to v1.4.1 (startup goal-intake)"
```

---

### Task 5: CHANGELOG + TODOS

**Files:**
- Modify: `$PD/CHANGELOG.md`, `$PD/TODOS.md`

- [ ] **Step 1: Read CHANGELOG top + the TODOS 1.4.1 item**

Run:
```bash
PD=/Users/brian/.claude/plugins/marketplaces/devteam/plugins/devteam
sed -n '1,6p' $PD/CHANGELOG.md
grep -n '1.4.1 — .*startup. guided goal-intake' $PD/TODOS.md
```
Expected: the CHANGELOG `# Changelog` + `## 1.4.0 …` entry; the TODOS Tier-1 1.4.1 item line.

- [ ] **Step 2: Add CHANGELOG 1.4.1 entry** above the `## 1.4.0` entry, matching the `## X.Y.Z — YYYY-MM-DD — Title` format:

```markdown
## 1.4.1 — 2026-06-20 — /startup guided goal-intake

### Added
- **Goal-intake for bare `/startup`.** Invoking `/startup` with no goal (and no `--goal-file`) no longer dead-ends — it runs a short main-thread Q&A that co-authors a goal, with an opt-in `council --lite` deferral ("I'm not sure — help me shape it") that proposes 1–3 candidate goal directions from your answers + repo/vault context. The assembled goal is written to `GOAL.md`, then flows into the existing CONTRACT phase.

### Notes
- Default Q&A path costs 0 dispatches; the unsure→council-lite path costs ~5 (counted toward the budget, opt-in).
- No change when a goal IS provided (inline or `--goal-file`). Backward compatible.
```

- [ ] **Step 3: Tick the TODOS item** — find the Tier-1 item starting `- [ ] **1.4.1 — \`/startup\` guided goal-intake.**` and change `- [ ]` to `- [x]`, appending ` _(shipped 1.4.1, 2026-06-20)_` to the title line.

- [ ] **Step 4: Validate**

Run:
```bash
PD=/Users/brian/.claude/plugins/marketplaces/devteam/plugins/devteam
grep -c '## 1.4.1' $PD/CHANGELOG.md
grep -c '\[x\] \*\*1.4.1' $PD/TODOS.md
```
Expected: `1` and `1`.

- [ ] **Step 5: Commit**

```bash
cd /Users/brian/.claude/plugins/marketplaces/devteam
git add plugins/devteam/CHANGELOG.md plugins/devteam/TODOS.md
git commit -m "docs(devteam): CHANGELOG 1.4.1 + tick goal-intake TODO"
```

---

### Task 6: Integration smoke

**Files:** none (validation only)

- [ ] **Step 1: Skill order + content**

Run:
```bash
PD=/Users/brian/.claude/plugins/marketplaces/devteam/plugins/devteam
grep -n '^## 0. Boot\|^## 0.5 INTAKE\|^## 1. CONTRACT phase' $PD/skills/startup/SKILL.md
```
Expected: Boot, then 0.5 INTAKE, then 1. CONTRACT — in that line order.

- [ ] **Step 2: Cross-references resolve (council still exists; no dangling)**

Run:
```bash
PD=/Users/brian/.claude/plugins/marketplaces/devteam/plugins/devteam
test -f $PD/skills/council/SKILL.md && echo "council OK"
grep -q 'council --lite' $PD/skills/startup/SKILL.md && echo "intake references council ✓"
grep -q 'INTAKE' $PD/commands/startup.md && echo "command references INTAKE ✓"
```
Expected: `council OK`, both `✓` lines.

- [ ] **Step 3: Manifests at 1.4.1, valid JSON**

Run:
```bash
R=/Users/brian/.claude/plugins/marketplaces/devteam
jq -e '.version=="1.4.1"' $R/plugins/devteam/.claude-plugin/plugin.json >/dev/null && echo "plugin 1.4.1 OK"
jq -e '.plugins[0].version=="1.4.1"' $R/.claude-plugin/marketplace.json >/dev/null && echo "marketplace 1.4.1 OK"
```
Expected: both OK.

- [ ] **Step 4: On feature branch with the commits**

Run:
```bash
cd /Users/brian/.claude/plugins/marketplaces/devteam
git branch --show-current
git log --oneline -7
```
Expected: branch `feat/startup-goal-intake`; commits for foundation, INTAKE skill, command branch, README, version bump, CHANGELOG/TODOS.

---

## Self-Review (completed by plan author)

**Spec coverage:**
- Spec §3 trigger (empty-only) → Task 1 INTAKE intro ("no goal AND no --goal-file") + Task 2 command branch.
- Spec §4.1 Q&A → Task 1 Step 2 (4 questions + escape).
- Spec §4.2 unsure→council-lite → Task 1 Step 2 (deferral block, synthesis goal, dispatch-count).
- Spec §4.3 assemble + write GOAL.md (no commit in intake) → Task 1 Step 2 ("Assemble + write GOAL.md").
- Spec §4.4 proceed to CONTRACT → Task 1 Step 3 (§1 goal-source note).
- Spec §4.5 hard fallback → Task 1 Step 2 ("Hard fallback").
- Spec §5 budget → encoded in the INTAKE text (0 default / ~5 unsure, dispatch-count).
- Spec §6 files → Tasks 1–5 cover every listed file.
- Spec §7 decisions → Q&A+deferral (Task 1), GOAL.md (Task 1), empty-only (Tasks 1–2).

**Placeholder scan:** No "TBD/TODO/implement later." Angle-bracket tokens inside the embedded SKILL content are that artifact's own template text, not plan gaps.

**Type/name consistency:** Section id `§0.5 INTAKE` and the escape phrase "I'm not sure — help me shape it" are identical across Tasks 1, 2, 3, 5. Version `1.4.1` consistent across Tasks 4–6. No `phase:` packet is introduced (the skill returns no packet), so no schema-enum risk this release.

**Known soft spots (acceptable):**
- The grep in Task 1 Step 4 uses `I.m not sure` (the `'` is matched by `.`) to avoid quote-escaping in the apostrophe — intentional.
- `council --lite` is invoked from the skill (main thread) — valid; council is a skill, not a nested subagent.
