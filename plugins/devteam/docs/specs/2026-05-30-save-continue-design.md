# `/save` + `/continue` — Devteam Session Continuity Design

**Date:** 2026-05-30
**Status:** Approved design, ready for implementation plan
**Author:** Brian + Claude (collaborative brainstorm)

---

## 1. Goal

Add seamless cross-session continuity to devteam. A user should be able to end a session — intentionally or via crash — and resume in a new session with minimal context loss and minimal token cost on re-entry.

Replaces `/lead-resume` and `/lead-abort` (deleted). Eventually replaces claude-sync's `/handoff` and `/continue-work` (deleted in Phase 4 — see Migration).

---

## 2. Scope

**In scope (this design):**
- `/save` skill + command — captures session state per project
- `/continue` skill + command — restores session state from a chosen save
- Storage at `~/.claude/devteam/saves/<slug>/` with rolling + named layout
- Autosave hook (change-based) + reminder hook + suggestion hook
- Migration from `/lead-resume` and `/lead-abort` (delete)
- Coordination with claude-sync's existing handoff/continue-work (Phase 2 coexistence, Phase 4 removal)

**Out of scope (separate sub-projects, do not design here):**
- Persistent Claude identity layer (SOUL.md / IDENTITY.md across surfaces)
- Cross-machine sync of saves via Obsidian / Google Drive
- Claude.ai web bridge via remote MCP
- Semantic memory store (claude-soul–style)
- One-command bootstrap onboarding

These are tracked as future sub-projects 2-6 in the broader "Claude brain" roadmap. This spec only concerns sub-project 1.

---

## 3. Architecture overview

Two new skills shipped in the devteam plugin, with companion hooks and storage:

```
plugins/devteam/
  skills/
    save/SKILL.md             # captures session state
    continue/SKILL.md         # restores session state
  commands/
    save.md                   # /save [name?]
    continue.md               # /continue [name|latest|list?]
  hooks/
    save-autosave.sh          # Stop + SessionEnd: change-based lightweight snapshot
    save-reminder.sh          # Stop: nag if commits without explicit /save
    save-suggest.sh           # extends existing session-start.sh: passive nag on session entry
```

**Two deletions:**
- `commands/lead-resume.md` (functionality folded into `/continue`)
- `commands/lead-abort.md` (functionality folded into `/save`; the `.last-phase=aborted` semantic has no consumer once `/lead-resume` is gone)

**Storage:**
```
~/.claude/devteam/saves/
  <project-slug>/
    latest.md                              # curated main, overwritten each save
    latest-decisions.md                    # optional sidecar, only if decisions captured
    .last-explicit                         # marker file: timestamp of most recent manual /save
    .autosave-mtime                        # marker file: state hash of last autosave write
    history/
      2026-05-30T15-08-spec-save-skill.md  # rolling, last 10 retained
      2026-05-30T14-22-pick-option-2.md
      ...
    named/
      pre-refactor.md                      # only via /save <name>; never rotated
```

`<project-slug>` derivation: `pwd | sed 's|/|-|g'` (matches handoff's convention for trivial future migration).

Slots into devteam's existing global persistence tier alongside `memory/`, `conventions/`, `projects/`.

---

## 4. Capture model: layered (minimal + decisions sidecar)

Targets minimal context cost on resume while preserving decision rationale on demand.

### 4.1 `latest.md` — main capture (target ≤1500 tokens, hard cap enforced)

```markdown
---
slug: my-project
project: my-project              # from .devteam/state/.project-name if devteam, else cwd basename
phase: BUILD                     # from .devteam/state/.last-phase if devteam, else "none"
saved_at: 2026-05-30T15:08:00Z
saved_by: explicit               # explicit | intent | autosave
session_id: <id>
name: spec-save-skill            # auto-generated kebab-slug for /continue <name> lookup
description: Spec the save skill design  # readable for /continue list display, ≤80 chars
git_branch: feature/save
git_head: abc123de
has_decisions: true              # presence of latest-decisions.md
---

# Goal
<1-2 sentences — what this project is trying to accomplish>

# Where we left off
<1-2 sentences — what was just done, what's mid-flight>

# Next steps
1. <concrete action>
2. <concrete action>
3. <concrete action>

# Open questions
- <blocker> (or "none")

# Devteam state                  # only if .devteam/state/ exists
- Phase: BUILD
- Partitions: 2/3 complete (fe done, api done, infra in-flight)
- Pending blocks: WAITING ON USER at [LEAD:#42] "should we use JWT or sessions?"
- Recent slack tail: <last 5 entries, one-line each>

# Recent commits
- abc123 Add /save skill scaffold
- def456 Wire Stop hook
```

### 4.2 `latest-decisions.md` — sidecar (target ≤3000 tokens, only written if decisions exist)

```markdown
---
slug: my-project
saved_at: 2026-05-30T15:08:00Z
parent: latest.md
---

# Decisions made this session

## Chose layered save (minimal + sidecar) over rich
**Why:** rich loads 2-4k tokens every session; layered defaults to ~700 with sidecar on demand.
**Pointer:** see slack [LEAD:#38]

## Chose /continue over /resume
**Why:** /resume collides with `claude --resume` CLI flag.
**Pointer:** this session

## Storage at ~/.claude/devteam/saves/<slug>/
**Why:** matches existing devteam global tier (memory/, conventions/, projects/). Global so /continue list works from anywhere; survives repo wipe.
**Pointer:** see slack [LEAD:#41]
```

### 4.3 Size enforcement

Both files have hard caps enforced at write time:

| File | Cap | On overflow |
|---|---|---|
| `latest.md` (explicit/intent) | 1500 tokens | Self-prompt: "compress to ≤1500; preserve cursor + next steps + blockers; drop narrative" |
| `latest-decisions.md` | 3000 tokens | Same self-compression loop |
| Autosave-written `latest.md` | 800 tokens | Hard-trim slack tail and commit list if over |

No manual taxonomy. No tags. No INDEX.md to maintain. The discipline is engineered in, not user-enforced.

### 4.4 Rotation

- On every explicit/intent save: copy current `latest.md` (if exists) to `history/<old-saved_at>-<old-name>.md` BEFORE overwriting. If old sidecar exists, append it as an inline `# Decisions` H2 section at the bottom of the historical file (single self-contained file).
- Trim `history/` to newest 10 by mtime, delete older.
- `named/<name>.md` is never rotated — opt-in permanence via `/save <name>`.
- Autosave writes do NOT rotate (autosave overwrites in place, no history entry).

---

## 5. Skill behavior

### 5.1 `/save [name?]`

```
1. Resolve paths
   - slug = pwd | sed 's|/|-|g'
   - savepoint_dir = ~/.claude/devteam/saves/<slug>
   - mkdir -p history/ named/

2. Gather state (in parallel)
   - Read .devteam/state/ if exists: .project-name, .last-phase, .flags,
     tail of slack.md (last ~20, filter to last 5 meaningful), pending blocks
     (grep WAITING ON USER), build-status.json / review-findings.json / test-results.json summaries
   - Read git: branch, HEAD short SHA, last 5 commit one-liners
   - Conversation context (model synthesizes): goal, where left off, next steps, blockers, decisions

3. Generate name + description (if no <name> arg given)
   - kebab-slug 3-5 words for filename + /continue <name> lookup
   - Readable 80-char description for /continue list display
   - Both auto-generated from same model thought

4. Compose latest.md
   - Fill frontmatter + sections per §4.1
   - Pre-flight token count: if >1500, self-prompt "compress to ≤1500"
   - Re-count; if still over, hard-trim narrative

5. Compose latest-decisions.md (only if decisions captured this session)
   - Same token cap enforcement (3000)
   - Set has_decisions: true in latest.md frontmatter

6. Rotate
   - If old latest.md exists:
     · Read it + sidecar (if exists)
     · If sidecar exists: append "# Decisions" H2 inline at bottom of historical file
     · Write to history/<old-saved_at>-<old-name>.md
   - Trim history/: keep newest 10 by mtime, delete the rest
   - If <name> was provided: ALSO copy new latest.md to named/<name>.md (never rotated)

7. Write
   - Atomic: write to .latest.md.tmp, mv to latest.md
   - Same for latest-decisions.md
   - Touch .last-explicit with current timestamp (consumed by save-reminder.sh)

8. Confirm to user
   SAVE WRITTEN
   ════════════
   Project:      my-project
   Name:         spec-save-skill
   Latest:       ~/.claude/devteam/saves/my-project/latest.md (847 tokens)
   Decisions:    +3 (sidecar written, 1240 tokens)
   History:      10 saves retained
```

### 5.2 `/continue [arg?]`

```
1. Resolve slug + save_dir

2. Branch on arg:

   a. No arg / "latest":
      - If no latest.md: "No save for <slug>. Run /save to create one."
        Also offer: "Other projects have saves. Try /continue list."
      - Else: print header (name, saved_at relative, summary line)
        Ask: "Load this save? [Y/n/list]"
        On Y: load (step 3); on n: exit; on list: jump to (c)

   b. <name>:
      - Look in named/<name>.md → load if found
      - Else look in history/ for filename containing <name> → load if found
      - Else: "No save named '<name>' for <slug>"

   c. "list":
      - Read history/*.md + named/*.md metadata (frontmatter only, no body)
      - AskUserQuestion menu, latest first, format:
        · "2h ago — spec-save-skill   Spec the save skill design   [BUILD, has decisions]"
        · "5h ago — pick-option-2     Picked layered capture       [PLAN]"
        · "[named] pre-refactor       Frozen state before refactor"
      - User picks → load that one

3. Load:
   - Read latest.md (or chosen save) → paste verbatim into context
   - If has_decisions: true:
     · Mention: "Decisions sidecar exists (N decisions, K tokens). Run /continue --with-decisions to load it too."
     · Don't auto-load — keeps context lean by default
   - If pending block exists (WAITING ON USER in devteam state):
     · Surface the question prominently
     · Ask: "Answer this now? [Y/n]"
     · On Y: take answer, re-invoke /lead with answer in brief (subsumes /lead-resume)
   - Optional drift check: git log since saved_at → if new commits, warn "drift detected, save may be stale"
```

---

## 6. Hooks

### 6.1 `hooks/save-autosave.sh` (Stop + SessionEnd)

Pure shell, no model. Runs ~50ms.

**Change-based logic:**
1. Compute current state hash: `git rev-parse HEAD` + mtime of `.devteam/state/slack.md`
2. If `.autosave-mtime` matches current hash → exit silently (no-op turn)
3. Else proceed to write

**Clobber protection:**
4. If existing `latest.md` has `saved_by: explicit` AND `saved_at` is within last 10 minutes → exit silently. Curated save wins.

**Write:**
5. Compose minimal `latest.md` (≤800 tokens) from disk state only:
   - Frontmatter: slug, saved_at, saved_by: autosave, git_branch, git_head, phase
   - Sections: Recent slack (last 20 lines), Recent commits (last 5)
   - No model-synthesized goal/next-steps (those stay empty in autosave)
6. Atomic write via .tmp → mv
7. Update `.autosave-mtime` with new state hash
8. Print one line to stdout: `📦 autosaved`

**Why "📦 autosaved" stays useful:** because change-based gating means most turns are no-ops (silent). When you see "📦 autosaved" it means meaningful state changed. After /save just ran, the next ~6 Stop events typically skip (clobber protection + likely no state change), confirming both autosave AND the grace rule work.

### 6.2 `hooks/save-reminder.sh` (Stop)

Pure shell, no model. Mirrors handoff's existing nag pattern.

**Logic:**
1. Read `.last-explicit` timestamp (skip if missing — no nag if user has never saved here)
2. Compare to `git log -1 --format=%ct` (most recent commit on current branch)
3. Skip if no commits past last-explicit time
4. Rate-limit: skip if `.session-nagged-<CLAUDE_SESSION_ID>` marker exists
5. Else print: `ℹ /save reminder: N commit(s) landed since last save. Run /save to capture context.`
6. Touch session marker; clean up markers older than 24h

### 6.3 `hooks/save-suggest.sh` (extends `hooks/session-start.sh`)

Pure shell. Appended to devteam's existing SessionStart hook (one entry per plugin in settings.json).

**Logic:**
1. Read `~/.claude/devteam/saves/<slug>/latest.md` (skip if missing)
2. Extract `name`, `description`, `saved_at` from frontmatter
3. Compute relative time (h ago / m ago / yesterday / N days ago)
4. Print: `📌 Save exists for this project (<rel>): "<description>". Run /continue to load.`

### 6.4 Intent detection (model guidance in `skills/save/SKILL.md`)

NOT a hook (hooks can't read conversation). Encoded as instruction in the save skill:

The model watches for end-of-session signals in normal conversation:
- "wrapping up", "have to go", "talk later", "let's continue tomorrow", "see you", "good night", "lunch break", "EOD", "done for today"

When detected:
1. Ask user: "Want me to save before you go? [Y/n]"
2. If yes: invoke `/save` (with `saved_by: intent` in frontmatter)
3. If implied name given ("save it as the auth refactor"): pass as `<name>` arg

**Always ask, never silent auto-save** — intent detection is heuristic and may be wrong.

---

## 7. Migration plan

### Phase 1: Ship devteam upgrade (now)

**Add to devteam plugin:**
- `skills/save/SKILL.md`, `skills/continue/SKILL.md`
- `commands/save.md`, `commands/continue.md`
- `hooks/save-autosave.sh`, `hooks/save-reminder.sh`, `hooks/save-suggest.sh`
- Extend `hooks/session-start.sh` to call `save-suggest.sh` at end
- Update `commands/lead-setup.md` to register the two new Stop hooks + SessionEnd hook
- Update `.claude-plugin/plugin.json` to declare new commands/skills/hooks

**Remove from devteam plugin:**
- `commands/lead-resume.md` (hard delete, no shim — user confirmed)
- `commands/lead-abort.md` (hard delete, no shim — user confirmed)

**Docs:**
- `CHANGELOG.md` — entry for new commands, removed commands, hooks
- `README.md` — commands table (add /save, /continue; remove /lead-resume, /lead-abort)
- `ARCHITECTURE.md` — update "Persistence model" section; note deprecations in "Why some original ideas were dropped"
- `docs/state-files.md` — add `saves/` to global table

**Version bump:** minor (new features + intentional command removal)

**handoff/continue-work in claude-sync: untouched.**

### Phase 2: Live-use validation (~2 weeks or 15 sessions, whichever is later)

- User adopts `/save` + `/continue` in daily flow
- Both systems coexist (handoff/continue-work still callable as backup)
- During this phase, both Stop hooks fire: handoff's nag + devteam's save-reminder + autosave confirmation
- Validate: list UX, capture content sufficiency, autosave grace rule, pending-block surfacing, auto-name quality, size caps

### Phase 3: claude-sync requires devteam

- Edit claude-sync's setup script to install devteam as part of bootstrap (`setup-gbrain` or equivalent)
- Document devteam as a hard dependency in claude-sync README

### Phase 4: Remove handoff/continue-work from claude-sync

- Delete `claude-sync/skills/handoff/`, `claude-sync/skills/continue-work/`
- Remove the handoff Stop-hook entry from `~/.claude/settings.json`:
  ```
  Stop hooks → remove: $HOME/.claude/skills/handoff/bin/stop-reminder.sh
  ```
- Optional cleanup: `rm -rf ~/.claude/projects/*/handoff/.sessions/`
- Add tombstone note in claude-sync README pointing at `/save` and `/continue`

### Coordination matrix

| Phase | devteam | claude-sync | settings.json |
|---|---|---|---|
| 1 | Add save/continue + hooks; remove lead-resume/abort; `lead-setup` registers new hooks | nothing | `lead-setup` adds 2 Stop hooks + 1 SessionEnd hook; SessionStart extended in-plugin |
| 2 | (live use) | nothing | (handoff nag still fires — ignore or comment out) |
| 3 | nothing | Update setup to require devteam | nothing |
| 4 | nothing | Delete handoff/continue-work skill dirs | Remove handoff Stop-hook entry |

### Cross-machine sync (Phase 1 stance)

Saves at `~/.claude/devteam/saves/` are **machine-local** in Phase 1. Add `/.claude/devteam/saves/` to claude-sync's `.gitignore` to prevent noisy autosave commits.

Cross-machine sync belongs to a separate sub-project (Obsidian vault on Google Drive) — out of scope here.

### Rollback path

If anything breaks badly in Phase 1:
- Pin previous devteam version via plugin marketplace
- handoff/continue-work untouched — keep working
- Worst case: revert devteam, file issue, retry

Phase 3+4 only proceed if Phase 2 is clean.

---

## 8. Risks and future considerations

| Risk | Mitigation |
|---|---|
| Autosave clobbers a curated save | 10-min grace rule on `saved_by: explicit` |
| Auto-generated description is misleading | User can override with `/save <name>` |
| Size cap truncates important content | Self-compression loop preserves cursor + blockers; user can re-save with `/save` to re-curate |
| `/continue list` shows stale saves | History capped at 10; named saves are explicit opt-in |
| Pending block surfaces wrong question | Re-prompted from latest `WAITING ON USER` in slack — same source `/lead-resume` used today |
| handoff and devteam saves drift apart during Phase 2 | User picks one as primary; both stores are non-destructive parallel |
| User runs `/lead-resume` muscle-memory after Phase 1 | Command not found; CHANGELOG documents the swap |
| Stop hook latency adds up | Change-based gating means most turns are no-ops (~5ms exit) |
| Future cross-machine sync wants different layout | Single canonical store at `~/.claude/devteam/saves/<slug>/` — easy to symlink into an Obsidian vault later |

---

## 9. Open items for the implementation plan

The implementation plan should specify:

1. Exact `lead-setup` settings.json edit logic (handle pre-existing hooks, idempotency)
2. Cap-enforcement loop — concrete prompt and retry count for compression
3. Slug collision handling if two cwds with different content produce the same slug (rare; document, no special handling)
4. Behavior when `.devteam/state/` is partially populated (e.g., `.last-phase` exists but slack doesn't)
5. Tests: at minimum, hook scripts under bash on macOS + linux; skill behavior via direct invocation
6. Documentation updates in detail
