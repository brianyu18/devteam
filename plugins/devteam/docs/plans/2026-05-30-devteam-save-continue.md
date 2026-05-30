# Devteam `/save` + `/continue` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `/save` and `/continue` skills + hooks to devteam for cross-session continuity; delete `/lead-resume` and `/lead-abort`; prepare claude-sync handoff/continue-work for Phase 4 deprecation.

**Architecture:** Two new model-driven skills (save, continue) wrapped by thin command frontends. Three shell-script hooks: change-based autosave (Stop + SessionEnd), commit-since-save reminder (Stop), and a SessionStart save-suggest appended to devteam's existing session-start hook. All saves live at `~/.claude/devteam/saves/<slug>/` with rolling 10-history + named slots + a decisions sidecar.

**Tech Stack:** POSIX shell (`#!/bin/sh`, `set -eu`), markdown skill/command files with YAML frontmatter, devteam plugin conventions (mkdir-mutex, atomic .tmp+mv, `DEVTEAM_*` env var overrides for testing).

**Reference spec:** `docs/specs/2026-05-30-save-continue-design.md`

---

## File Structure

**Create (8 files):**
- `plugins/devteam/skills/save/SKILL.md` — model-driven save logic
- `plugins/devteam/skills/continue/SKILL.md` — model-driven continue logic
- `plugins/devteam/commands/save.md` — `/save [name?]` frontend
- `plugins/devteam/commands/continue.md` — `/continue [arg?]` frontend
- `plugins/devteam/hooks/save-autosave.sh` — Stop + SessionEnd autosave
- `plugins/devteam/hooks/save-reminder.sh` — Stop nag
- `plugins/devteam/bin/test-save-autosave.sh` — autosave smoke test
- `plugins/devteam/bin/test-save-reminder.sh` — reminder smoke test

**Modify (8 files):**
- `plugins/devteam/hooks/session-start.sh` — append save-suggest logic
- `plugins/devteam/hooks/hooks.json.example` — document new hook entries
- `plugins/devteam/commands/lead-setup.md` — register two new hooks
- `plugins/devteam/.claude-plugin/plugin.json` — bump version 1.0.1 → 1.1.0
- `plugins/devteam/CHANGELOG.md` — release entry
- `plugins/devteam/README.md` — commands table
- `plugins/devteam/ARCHITECTURE.md` — persistence model section
- `plugins/devteam/docs/state-files.md` — global table

**Delete (2 files):**
- `plugins/devteam/commands/lead-resume.md`
- `plugins/devteam/commands/lead-abort.md`

**Modify in claude-sync repo (1 file):**
- `claude-sync/.gitignore` — add `/.claude/devteam/saves/`

All paths below are relative to the devteam repo root unless noted.

---

## Task 1: Autosave hook test (failing first, TDD)

**Files:**
- Create: `plugins/devteam/bin/test-save-autosave.sh`

- [ ] **Step 1: Write the failing test**

```sh
#!/bin/sh
# Smoke test for save-autosave.sh
# Covers: write on first run, change-based skip on no-op turn, clobber protection
# of fresh explicit save (within 10min).
set -eu

TMPROOT=$(mktemp -d)
export DEVTEAM_SAVES_HOME="$TMPROOT/saves"
export HOME="$TMPROOT/home"  # isolate from real ~/.claude/devteam/saves
mkdir -p "$DEVTEAM_SAVES_HOME" "$HOME/.claude/devteam/saves"
cd "$TMPROOT"

# Minimal fake git repo so `git rev-parse HEAD` returns something stable
git init -q .
git -c user.email=t@t -c user.name=t commit --allow-empty -q -m "seed"

HELPER="$OLDPWD/plugins/devteam/hooks/save-autosave.sh"
[ -x "$HELPER" ] || { echo "FAIL: hook not executable: $HELPER"; exit 1; }

SLUG=$(echo "$TMPROOT" | sed 's|/|-|g')
DIR="$DEVTEAM_SAVES_HOME/$SLUG"

# 1. First run writes latest.md
"$HELPER" || { echo "FAIL: first run errored"; exit 1; }
[ -f "$DIR/latest.md" ] || { echo "FAIL: latest.md not created"; exit 1; }
grep -q "saved_by: autosave" "$DIR/latest.md" || { echo "FAIL: saved_by not autosave"; exit 1; }

# 2. Second run with no state change → no-op (mtime unchanged)
MTIME1=$(stat -f %m "$DIR/latest.md" 2>/dev/null || stat -c %Y "$DIR/latest.md")
sleep 1
"$HELPER" || { echo "FAIL: second run errored"; exit 1; }
MTIME2=$(stat -f %m "$DIR/latest.md" 2>/dev/null || stat -c %Y "$DIR/latest.md")
[ "$MTIME1" = "$MTIME2" ] || { echo "FAIL: change-based gating did not skip no-op turn"; exit 1; }

# 3. Clobber protection: explicit save within 10min → autosave skips
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > "$DIR/latest.md" <<EOF
---
slug: $SLUG
saved_at: $NOW
saved_by: explicit
name: manual-save
---
# Manual content
EOF
# Force a state change so autosave WOULD run if not for clobber rule
git -c user.email=t@t -c user.name=t commit --allow-empty -q -m "trigger change"
"$HELPER" || { echo "FAIL: third run errored"; exit 1; }
grep -q "saved_by: explicit" "$DIR/latest.md" || { echo "FAIL: clobber protection failed — explicit save was overwritten"; exit 1; }
grep -q "Manual content" "$DIR/latest.md" || { echo "FAIL: explicit save body was overwritten"; exit 1; }

echo "OK: all save-autosave smoke tests passed"
rm -rf "$TMPROOT"
```

- [ ] **Step 2: Make test executable and run to verify it fails**

```bash
chmod +x plugins/devteam/bin/test-save-autosave.sh
./plugins/devteam/bin/test-save-autosave.sh
```

Expected: `FAIL: hook not executable: .../plugins/devteam/hooks/save-autosave.sh` (hook doesn't exist yet)

---

## Task 2: Autosave hook implementation

**Files:**
- Create: `plugins/devteam/hooks/save-autosave.sh`

- [ ] **Step 1: Write the autosave hook**

```sh
#!/bin/sh
# Stop + SessionEnd hook. Change-based gating: only writes if disk state changed
# since last autosave. Respects 10-min grace window on explicit saves so a fresh
# curated save is not clobbered by a thin autosave.
#
# Overrides for testing:
#   DEVTEAM_SAVES_HOME — override default ~/.claude/devteam/saves
set -eu

SAVES_HOME="${DEVTEAM_SAVES_HOME:-$HOME/.claude/devteam/saves}"
SLUG=$(pwd | sed 's|/|-|g')
DIR="$SAVES_HOME/$SLUG"
mkdir -p "$DIR/history" "$DIR/named"

# 1. Change-based gating
GIT_HEAD=$(git rev-parse HEAD 2>/dev/null || echo "no-git")
SLACK_MTIME=$(stat -f %m .devteam/state/slack.md 2>/dev/null || stat -c %Y .devteam/state/slack.md 2>/dev/null || echo "0")
STATE_HASH="${GIT_HEAD}-${SLACK_MTIME}"
if [ -f "$DIR/.autosave-mtime" ] && [ "$(cat "$DIR/.autosave-mtime")" = "$STATE_HASH" ]; then
  exit 0  # no state change since last autosave — silent no-op
fi

# 2. Clobber protection
if [ -f "$DIR/latest.md" ]; then
  SAVED_BY=$(awk -F': ' '/^saved_by:/ {print $2; exit}' "$DIR/latest.md" 2>/dev/null || echo "")
  SAVED_AT=$(awk -F': ' '/^saved_at:/ {print $2; exit}' "$DIR/latest.md" 2>/dev/null || echo "")
  if [ "$SAVED_BY" = "explicit" ] && [ -n "$SAVED_AT" ]; then
    # Convert ISO-8601 to epoch (best-effort; BSD/GNU date differ)
    SAVED_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$SAVED_AT" "+%s" 2>/dev/null || date -d "$SAVED_AT" "+%s" 2>/dev/null || echo "0")
    if [ "$SAVED_EPOCH" -gt 0 ]; then
      AGE=$(( $(date +%s) - SAVED_EPOCH ))
      if [ "$AGE" -lt 600 ]; then
        exit 0  # fresh curated save — do not clobber
      fi
    fi
  fi
fi

# 3. Compose minimal latest.md (autosave content only — no model synthesis)
TMP="$DIR/.latest.md.tmp"
{
  echo "---"
  echo "slug: $SLUG"
  echo "saved_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "saved_by: autosave"
  echo "git_branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo none)"
  echo "git_head: $(git rev-parse --short HEAD 2>/dev/null || echo none)"
  if [ -f .devteam/state/.last-phase ]; then
    echo "phase: $(cat .devteam/state/.last-phase)"
  fi
  echo "---"
  echo ""
  echo "# Autosaved snapshot"
  echo ""
  echo "_Lightweight crash-safety snapshot. Run /save for a curated save._"
  echo ""
  if [ -f .devteam/state/slack.md ]; then
    echo "## Recent slack"
    tail -20 .devteam/state/slack.md
    echo ""
  fi
  echo "## Recent commits"
  git log --oneline -5 2>/dev/null || echo "(no git)"
} > "$TMP" && mv "$TMP" "$DIR/latest.md"

# 4. Record state hash for next change-gating
echo "$STATE_HASH" > "$DIR/.autosave-mtime"

# 5. Confirmation message (only when we actually wrote)
echo "📦 autosaved"
```

- [ ] **Step 2: Make hook executable**

```bash
chmod +x plugins/devteam/hooks/save-autosave.sh
```

- [ ] **Step 3: Run test to verify it passes**

```bash
./plugins/devteam/bin/test-save-autosave.sh
```

Expected: `OK: all save-autosave smoke tests passed`

- [ ] **Step 4: Commit**

```bash
git add plugins/devteam/hooks/save-autosave.sh plugins/devteam/bin/test-save-autosave.sh
git commit -m "feat(devteam): add save-autosave hook with change-based gating + clobber protection"
```

---

## Task 3: Reminder hook test (failing first)

**Files:**
- Create: `plugins/devteam/bin/test-save-reminder.sh`

- [ ] **Step 1: Write the failing test**

```sh
#!/bin/sh
# Smoke test for save-reminder.sh
# Covers: silent when no .last-explicit, prints when commits exceed last-explicit,
# silent on re-fire within same session (marker).
set -eu

TMPROOT=$(mktemp -d)
export DEVTEAM_SAVES_HOME="$TMPROOT/saves"
export HOME="$TMPROOT/home"
export CLAUDE_SESSION_ID="test-session-$$"
mkdir -p "$DEVTEAM_SAVES_HOME"
cd "$TMPROOT"
git init -q .
git -c user.email=t@t -c user.name=t commit --allow-empty -q -m "seed"

HELPER="$OLDPWD/plugins/devteam/hooks/save-reminder.sh"
[ -x "$HELPER" ] || { echo "FAIL: hook not executable: $HELPER"; exit 1; }

SLUG=$(echo "$TMPROOT" | sed 's|/|-|g')
DIR="$DEVTEAM_SAVES_HOME/$SLUG"
mkdir -p "$DIR"

# 1. Silent when .last-explicit doesn't exist
OUT=$("$HELPER" 2>&1 || true)
[ -z "$OUT" ] || { echo "FAIL: expected silent (no last-explicit), got: $OUT"; exit 1; }

# 2. Set last-explicit 1 hour ago, make a commit, expect nag
date -u -v-1H +%s > "$DIR/.last-explicit" 2>/dev/null || date -u -d "1 hour ago" +%s > "$DIR/.last-explicit"
git -c user.email=t@t -c user.name=t commit --allow-empty -q -m "new commit"
OUT=$("$HELPER" 2>&1 || true)
echo "$OUT" | grep -q "/save reminder" || { echo "FAIL: expected /save reminder, got: $OUT"; exit 1; }

# 3. Re-fire in same session → silent (marker rate-limit)
OUT2=$("$HELPER" 2>&1 || true)
[ -z "$OUT2" ] || { echo "FAIL: expected silent on re-fire same session, got: $OUT2"; exit 1; }

echo "OK: all save-reminder smoke tests passed"
rm -rf "$TMPROOT"
```

- [ ] **Step 2: Make test executable and verify it fails**

```bash
chmod +x plugins/devteam/bin/test-save-reminder.sh
./plugins/devteam/bin/test-save-reminder.sh
```

Expected: `FAIL: hook not executable: .../plugins/devteam/hooks/save-reminder.sh`

---

## Task 4: Reminder hook implementation

**Files:**
- Create: `plugins/devteam/hooks/save-reminder.sh`

- [ ] **Step 1: Write the reminder hook**

```sh
#!/bin/sh
# Stop hook. Nags user once per session if commits have landed since their last
# explicit /save. Silent when:
#   - No .last-explicit marker (user has never saved here)
#   - No commits since last-explicit
#   - Already nagged this session (rate-limit via CLAUDE_SESSION_ID marker)
#
# Mirrors handoff's stop-reminder.sh pattern.
set -u

SAVES_HOME="${DEVTEAM_SAVES_HOME:-$HOME/.claude/devteam/saves}"
SLUG=$(pwd | sed 's|/|-|g')
DIR="$SAVES_HOME/$SLUG"

# Silent if no last-explicit marker
[ -f "$DIR/.last-explicit" ] || exit 0

LAST_EXPLICIT=$(cat "$DIR/.last-explicit" 2>/dev/null || echo "")
[ -n "$LAST_EXPLICIT" ] || exit 0

# Session marker for rate-limiting
SESSION_KEY="${CLAUDE_SESSION_ID:-$PPID}"
MARKER_DIR="$DIR/.sessions"
mkdir -p "$MARKER_DIR" 2>/dev/null || true
MARKER="$MARKER_DIR/nagged-$SESSION_KEY"
[ -f "$MARKER" ] && exit 0

# Most recent commit on current branch
LAST_COMMIT_TS=$(git log -1 --format=%ct 2>/dev/null || echo "")
[ -n "$LAST_COMMIT_TS" ] || exit 0
[ "$LAST_COMMIT_TS" -le "$LAST_EXPLICIT" ] && exit 0

COMMITS_SINCE=$(git log --since="@$LAST_EXPLICIT" --oneline 2>/dev/null | wc -l | tr -d ' ')
[ "$COMMITS_SINCE" -eq 0 ] && exit 0

touch "$MARKER" 2>/dev/null || true
# Clean stale markers (>24h)
find "$MARKER_DIR" -maxdepth 1 -name 'nagged-*' -mmin +1440 -delete 2>/dev/null || true

echo "ℹ /save reminder: $COMMITS_SINCE commit(s) landed since last save. Run /save to capture context."
exit 0
```

- [ ] **Step 2: Make hook executable**

```bash
chmod +x plugins/devteam/hooks/save-reminder.sh
```

- [ ] **Step 3: Run test to verify it passes**

```bash
./plugins/devteam/bin/test-save-reminder.sh
```

Expected: `OK: all save-reminder smoke tests passed`

- [ ] **Step 4: Commit**

```bash
git add plugins/devteam/hooks/save-reminder.sh plugins/devteam/bin/test-save-reminder.sh
git commit -m "feat(devteam): add save-reminder hook (nag on commits without explicit save)"
```

---

## Task 5: Extend session-start.sh with save-suggest

**Files:**
- Modify: `plugins/devteam/hooks/session-start.sh`

- [ ] **Step 1: Replace session-start.sh with extended version**

```sh
#!/bin/sh
# devteam SessionStart hook — surfaces project status when entering a repo with
# .devteam/state/, and surfaces existing save if one exists for the cwd.
set -eu

STATE_DIR="${PWD}/.devteam/state"
SAVES_HOME="${DEVTEAM_SAVES_HOME:-$HOME/.claude/devteam/saves}"
SLUG=$(pwd | sed 's|/|-|g')
SAVE_FILE="$SAVES_HOME/$SLUG/latest.md"

# Part 1 — devteam project status (existing behavior)
if [ -d "$STATE_DIR" ]; then
  PROJECT="$(cat "$STATE_DIR/.project-name" 2>/dev/null || echo "unnamed")"
  LAST_PHASE="$(cat "$STATE_DIR/.last-phase" 2>/dev/null || echo "?")"
  MODE="$(cat "${PWD}/.devteam/mode" 2>/dev/null || echo "work-together")"
  cat <<EOF
[devteam] Active project: $PROJECT (mode: $MODE, last phase: $LAST_PHASE)
[devteam] Run /lead-status to inspect, /lead to resume.
EOF
fi

# Part 2 — save suggestion (new)
if [ -f "$SAVE_FILE" ]; then
  NAME=$(awk -F': ' '/^name:/ {print $2; exit}' "$SAVE_FILE" 2>/dev/null || echo "")
  DESC=$(awk -F': ' '/^description:/ {sub(/^description: /, ""); print; exit}' "$SAVE_FILE" 2>/dev/null || echo "")
  SAVED_AT=$(awk -F': ' '/^saved_at:/ {print $2; exit}' "$SAVE_FILE" 2>/dev/null || echo "")
  # Best-effort relative time
  if [ -n "$SAVED_AT" ]; then
    SAVED_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$SAVED_AT" "+%s" 2>/dev/null || date -d "$SAVED_AT" "+%s" 2>/dev/null || echo "0")
    if [ "$SAVED_EPOCH" -gt 0 ]; then
      DELTA=$(( $(date +%s) - SAVED_EPOCH ))
      if [ "$DELTA" -lt 3600 ]; then
        REL="$((DELTA / 60))m ago"
      elif [ "$DELTA" -lt 86400 ]; then
        REL="$((DELTA / 3600))h ago"
      else
        REL="$((DELTA / 86400))d ago"
      fi
    else
      REL="$SAVED_AT"
    fi
  else
    REL="unknown time"
  fi
  LABEL="${DESC:-$NAME}"
  LABEL="${LABEL:-unnamed save}"
  echo "📌 Save exists for this project ($REL): \"$LABEL\". Run /continue to load."
fi
```

- [ ] **Step 2: Test session-start manually**

```bash
cd /tmp && mkdir -p test-sessionstart && cd test-sessionstart
DEVTEAM_SAVES_HOME=/tmp/test-saves bash "$OLDPWD/plugins/devteam/hooks/session-start.sh"
```

Expected: silent (no .devteam/state, no save). No errors.

- [ ] **Step 3: Commit**

```bash
git add plugins/devteam/hooks/session-start.sh
git commit -m "feat(devteam): extend session-start hook with save suggestion"
```

---

## Task 6: Update hooks.json.example to document new hooks

**Files:**
- Modify: `plugins/devteam/hooks/hooks.json.example`

- [ ] **Step 1: Replace with full example**

```json
{
  "_comment": "devteam hooks — SessionStart surfaces project status + save suggestion; Stop runs save-autosave (change-based) and save-reminder (commit nag); SessionEnd runs save-autosave as the final backstop. Activated via /lead-setup which writes these entries to ~/.claude/settings.json. Rename to hooks.json to enable plugin-local activation (rarely needed; settings-level registration is the standard path).",
  "SessionStart": [
    { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh" }
  ],
  "Stop": [
    { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/save-autosave.sh" },
    { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/save-reminder.sh", "timeout": 5 }
  ],
  "SessionEnd": [
    { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/save-autosave.sh" }
  ]
}
```

- [ ] **Step 2: Commit**

```bash
git add plugins/devteam/hooks/hooks.json.example
git commit -m "docs(devteam): document new save hooks in hooks.json.example"
```

---

## Task 7: Save skill (SKILL.md)

**Files:**
- Create: `plugins/devteam/skills/save/SKILL.md`

- [ ] **Step 1: Write the save skill**

```markdown
---
name: save
description: Use to capture the current session's state to disk as a savepoint, so a future session can resume with minimal context loss. Invoked directly via /save [name?], or self-invoked when the model detects user intent to end the session ("wrapping up", "have to go", etc.) after asking the user for consent.
---

# SAVE

You own the SAVE action. Capture the current session's state into a curated savepoint at `~/.claude/devteam/saves/<slug>/`.

## When to invoke

- User typed `/save` (explicit)
- User typed `/save <name>` (explicit with override name)
- You detected end-of-session intent in conversation ("wrapping up", "have to go", "talk later", "let's continue tomorrow", "see you", "good night", "lunch break", "EOD", "done for today") AND user confirmed via "Want me to save before you go? [Y/n]" → yes

Never auto-save silently on intent. Always ask first.

## Inputs

- `<name>` arg if provided (else auto-generate kebab-slug + readable description)
- `.devteam/state/` if it exists (project name, .last-phase, slack tail, pending blocks, build/review/test status files)
- `git` (branch, HEAD, last 5 commits)
- Current conversation context (your job to synthesize goal / where left off / next steps / blockers / decisions)

## Steps

1. **Resolve paths.**
   ```sh
   SLUG=$(pwd | sed 's|/|-|g')
   DIR="$HOME/.claude/devteam/saves/$SLUG"
   mkdir -p "$DIR/history" "$DIR/named"
   ```

2. **Gather disk state in parallel:**
   - `.devteam/state/.project-name`, `.last-phase`, `.flags`
   - `tail -n 20 .devteam/state/slack.md`; filter to the 5 most meaningful (last LEAD/specialist entries, not bookkeeping)
   - `grep "WAITING ON USER" .devteam/state/slack.md | tail -n 1` for pending blocks
   - Read summaries from `build-status.json`, `review-findings.json`, `test-results.json` if present
   - `git rev-parse --abbrev-ref HEAD`, `git rev-parse --short HEAD`, `git log --oneline -5`

3. **Synthesize conversation context from your turn history:**
   - Goal: 1-2 sentences on what this project is trying to do
   - Where we left off: 1-2 sentences on the most recent action and what's mid-flight
   - Next steps: 3-5 concrete actions
   - Open questions: any blockers (or "none")
   - Decisions made this session: each as (title, why, pointer)

4. **Generate name + description (if no `<name>` arg given):**
   - `name`: 3-5 word kebab-slug describing session focus (e.g. `fix-auth-race-condition`)
   - `description`: ≤80 char human-readable (e.g. `Fix auth race condition in login flow`)

5. **Compose `latest.md` per the schema in `docs/specs/2026-05-30-save-continue-design.md` §4.1.**
   - Hard cap: 1500 tokens (estimate ~4 chars/token). If over: self-compress preserving cursor/next-steps/blockers, drop narrative.

6. **If decisions exist, compose `latest-decisions.md` per §4.2.**
   - Hard cap: 3000 tokens. Same compression rule.
   - Set `has_decisions: true` in latest.md frontmatter.

7. **Rotate:**
   - If old `latest.md` exists: read old + old sidecar; write to `history/<old-saved_at>-<old-name>.md`. If sidecar existed, append it as `# Decisions` H2 inline at bottom of historical file.
   - Trim `history/` to newest 10 by mtime (use `ls -t history/ | tail -n +11 | xargs rm -f`).
   - If `<name>` arg given: copy new latest.md to `named/<name>.md` (never rotated).

8. **Write atomically:**
   ```sh
   # latest.md
   cat > "$DIR/.latest.md.tmp" <<EOF...EOF
   mv "$DIR/.latest.md.tmp" "$DIR/latest.md"
   # latest-decisions.md (if applicable)
   cat > "$DIR/.latest-decisions.md.tmp" <<EOF...EOF
   mv "$DIR/.latest-decisions.md.tmp" "$DIR/latest-decisions.md"
   ```

9. **Touch `.last-explicit` marker** (consumed by save-reminder.sh):
   ```sh
   date +%s > "$DIR/.last-explicit"
   ```

10. **If `.devteam/state/` exists**, append a SUMMARY entry to slack:
    ```sh
    "$PLUGIN_PATH/bin/slack-append.sh" "[SAVE#] INFO  savepoint written: <name>"
    ```

11. **Report to user:**
    ```
    SAVE WRITTEN
    ════════════
    Project:    <project>
    Name:       <name>
    Latest:     <path> (<token-count> tokens)
    Decisions:  +N (sidecar written, K tokens)   # only if has_decisions
    History:    N saves retained
    ```

## Frontmatter contract

Always include in `latest.md` frontmatter:
- `slug`, `project`, `phase`, `saved_at` (UTC ISO-8601), `saved_by` (explicit | intent), `session_id`, `name`, `description`, `git_branch`, `git_head`, `has_decisions`
```

- [ ] **Step 2: Commit**

```bash
git add plugins/devteam/skills/save/SKILL.md
git commit -m "feat(devteam): add save skill — model-driven curated savepoint capture"
```

---

## Task 8: Continue skill (SKILL.md)

**Files:**
- Create: `plugins/devteam/skills/continue/SKILL.md`

- [ ] **Step 1: Write the continue skill**

```markdown
---
name: continue
description: Use to resume a prior session from a saved savepoint at the start of a new session. Loads minimal curated state by default; offers list/named/decisions-sidecar variants. Subsumes the prior /lead-resume by surfacing any WAITING ON USER block and offering to answer it.
---

# CONTINUE

You own the CONTINUE action. Load a prior savepoint from `~/.claude/devteam/saves/<slug>/` and resume work.

## Invocation forms

- `/continue` — load latest save for current project
- `/continue latest` — same as above
- `/continue list` — show menu of recent + named saves; user picks
- `/continue <name>` — load named or history save by name
- `/continue --with-decisions` — load latest including decisions sidecar

## Steps

1. **Resolve paths.**
   ```sh
   SLUG=$(pwd | sed 's|/|-|g')
   DIR="$HOME/.claude/devteam/saves/$SLUG"
   ```

2. **Branch on arg:**

   ### (a) No arg / `latest` / `--with-decisions`
   - If `$DIR/latest.md` does not exist:
     - Print: `No save for <slug>. Run /save to create one.`
     - If any other `$HOME/.claude/devteam/saves/*/latest.md` exists: also print `Other projects have saves — run /continue list to see all.`
     - Exit.
   - Else: read frontmatter fields (`name`, `description`, `saved_at`, `has_decisions`).
   - Print header with description + relative time.
   - Use AskUserQuestion: "Load this save? [Y/n/list]". On Y → step 3; on n → exit; on list → branch (c).
   - If `--with-decisions` was passed: also read `latest-decisions.md` and include in step 3.

   ### (b) `<name>` (any non-keyword arg)
   - Look in `$DIR/named/<name>.md` first.
   - Fallback: find latest `$DIR/history/*<name>*.md` by mtime.
   - If neither: `No save named '<name>' for <slug>` → exit.
   - Read frontmatter; jump to step 3.

   ### (c) `list`
   - Read frontmatter (name, description, saved_at, phase, has_decisions) from every `$DIR/history/*.md` and `$DIR/named/*.md`.
   - Build AskUserQuestion menu, latest first. Format each item:
     ```
     <relative-time> — <name>   <description>   [<phase>, has_decisions?]
     ```
     Named items get `[named]` prefix.
   - User picks → load that save (step 3).

3. **Load the chosen save into context:**
   - Paste `latest.md` (or chosen save) body verbatim. Do not summarize.
   - If `has_decisions: true` and sidecar was NOT explicitly requested: print `Decisions sidecar exists (N decisions). Run /continue --with-decisions to load it.`
   - If `--with-decisions` requested AND sidecar exists: also paste `latest-decisions.md` verbatim.

4. **Surface pending blocks** (devteam-aware — subsumes /lead-resume):
   - Read `.devteam/state/slack.md` if it exists. Grep most recent `WAITING ON USER` entry.
   - If found AND the save's `saved_at` predates the slack entry's timestamp: surface the pending question prominently.
   - Use AskUserQuestion: "Answer the pending question now? [Y/n]".
   - On Y: take the user's answer, re-invoke `/lead` with the answer in the brief. LEAD picks up from `.last-phase` and re-dispatches the blocked specialist.

5. **Drift check** (optional, recommended):
   - Compare `git log --since="@<saved_at-epoch>" --oneline | wc -l` against expected.
   - If new commits since save: print `⚠ Drift detected: N commits since save_at. The save may be stale relative to current code.`

6. **Confirm to user:**
   ```
   RESUMED FROM SAVE
   ═════════════════
   Name:       <name>
   Saved:      <relative-time>
   Description: <description>
   Decisions loaded: yes|no
   Pending block: answered|ignored|none
   ```
```

- [ ] **Step 2: Commit**

```bash
git add plugins/devteam/skills/continue/SKILL.md
git commit -m "feat(devteam): add continue skill — resume from savepoint with pending-block handling"
```

---

## Task 9: Command frontends (`/save` and `/continue`)

**Files:**
- Create: `plugins/devteam/commands/save.md`
- Create: `plugins/devteam/commands/continue.md`

- [ ] **Step 1: Write `/save` command**

```markdown
---
description: Capture the current session's state as a savepoint for cross-session continuity. Optional <name> arg pins the save to ~/.claude/devteam/saves/<slug>/named/ (never rotated). Without args, an auto-generated kebab-slug name + readable description are produced.
---

The user invoked `/save` with: $ARGUMENTS

Invoke the `save` skill. Pass `$ARGUMENTS` as the optional `<name>` if present.

If no `$ARGUMENTS`, you generate the name + description from session context per the skill spec.
```

- [ ] **Step 2: Write `/continue` command**

```markdown
---
description: Resume a prior session from a savepoint. Forms: /continue (load latest), /continue list (menu), /continue <name> (load named or history match), /continue --with-decisions (load latest + decisions sidecar).
---

The user invoked `/continue` with: $ARGUMENTS

Invoke the `continue` skill. Pass `$ARGUMENTS` verbatim — the skill resolves keywords (`latest`, `list`, `--with-decisions`) and treats any other non-empty arg as a `<name>` lookup.
```

- [ ] **Step 3: Commit**

```bash
git add plugins/devteam/commands/save.md plugins/devteam/commands/continue.md
git commit -m "feat(devteam): add /save and /continue command frontends"
```

---

## Task 10: Delete `/lead-resume` and `/lead-abort`

**Files:**
- Delete: `plugins/devteam/commands/lead-resume.md`
- Delete: `plugins/devteam/commands/lead-abort.md`

- [ ] **Step 1: Delete the files**

```bash
rm plugins/devteam/commands/lead-resume.md plugins/devteam/commands/lead-abort.md
```

- [ ] **Step 2: Search for any remaining references and fix them**

```bash
grep -rn "lead-resume\|lead-abort" plugins/devteam/ --exclude-dir=.git
```

Expected: references in `session-start.sh` (already removed in Task 5), README, ARCHITECTURE — these will be updated in later tasks. Any references in skill files or commands need to be removed now.

- [ ] **Step 3: If any in-task references remain, fix them**

If `grep` returns references inside `skills/`, `commands/`, or `hooks/` (other than already-handled docs), edit those files to remove or replace the references with `/continue` and `/save`.

- [ ] **Step 4: Commit**

```bash
git add -A plugins/devteam/commands/
git commit -m "feat(devteam)!: remove /lead-resume and /lead-abort (folded into /continue and /save)"
```

---

## Task 11: Update `/lead-setup` to register new hooks

**Files:**
- Modify: `plugins/devteam/commands/lead-setup.md`

- [ ] **Step 1: Read current lead-setup.md**

```bash
cat plugins/devteam/commands/lead-setup.md
```

(Use the current content as your starting point. The change is to step 5 — extend the hook registration to also add Stop and SessionEnd entries.)

- [ ] **Step 2: Replace lead-setup.md with updated version**

```markdown
---
description: One-time devteam setup — registers SessionStart, Stop, and SessionEnd hooks in ~/.claude/settings.json, seeds the conventions library to ~/.claude/devteam/conventions/, creates the saves/ directory, and verifies plugin dependencies. Idempotent.
---

The user invoked `/lead-setup` with: $ARGUMENTS

1. **Resolve plugin install path.** Use `${CLAUDE_PLUGIN_ROOT}` if set; otherwise read `~/.claude/plugins/installed_plugins.json` and locate the `devteam` entry. Stash as `$PLUGIN_PATH`.

2. **Dependency check.** Read `~/.claude/plugins/installed_plugins.json`:
   - `superpowers` (REQUIRED) — refuse with install command + exit if absent.
   - `gstack` (SOFT) — warn that REVIEW + SHIP will degrade if absent.

3. **Create global directories** (idempotent, no overwrite):
   - `~/.claude/devteam/memory/`
   - `~/.claude/devteam/conventions/`
   - `~/.claude/devteam/projects/`
   - `~/.claude/devteam/saves/`

4. **Seed conventions library.** If `~/.claude/devteam/conventions/index.json` does NOT exist, copy contents of `$PLUGIN_PATH/conventions-seed/` to `~/.claude/devteam/conventions/`. If `index.json` already exists: print `[lead-setup] Conventions library exists at ~/.claude/devteam/conventions/ — no changes.` and skip — never overwrite user customizations.

5. **Register hooks.** Use the `update-config` skill (or edit directly) to add entries to `~/.claude/settings.json`. Each entry should be checked for exact-path-match before adding (idempotent):

   **SessionStart:**
   ```json
   { "type": "command", "command": "$PLUGIN_PATH/hooks/session-start.sh" }
   ```

   **Stop (two entries):**
   ```json
   { "type": "command", "command": "$PLUGIN_PATH/hooks/save-autosave.sh" }
   { "type": "command", "command": "$PLUGIN_PATH/hooks/save-reminder.sh", "timeout": 5 }
   ```

   **SessionEnd:**
   ```json
   { "type": "command", "command": "$PLUGIN_PATH/hooks/save-autosave.sh" }
   ```

   For each entry: if already present (exact path match) → print `[lead-setup] Hook already registered: <event> <name>` and skip.

6. **Ensure scripts are executable.** `chmod +x $PLUGIN_PATH/bin/*.sh $PLUGIN_PATH/hooks/*.sh` (idempotent).

7. **Report.** Print one line per step: `OK` / `SKIPPED` / `WARN`. Final line:
   - First-run: `[lead-setup] Setup complete. Run /lead <task> to start your first project.`
   - Idempotent re-run with no changes: `[lead-setup] All hooks already registered. Conventions library exists at ~/.claude/devteam/conventions/ — no changes.`
```

- [ ] **Step 3: Commit**

```bash
git add plugins/devteam/commands/lead-setup.md
git commit -m "feat(devteam): extend /lead-setup to register save-autosave and save-reminder hooks"
```

---

## Task 12: Bump plugin version

**Files:**
- Modify: `plugins/devteam/.claude-plugin/plugin.json`

- [ ] **Step 1: Bump version from 1.0.1 to 1.1.0**

Open `plugins/devteam/.claude-plugin/plugin.json` and change:

```json
"version": "1.0.1",
```

to:

```json
"version": "1.1.0",
```

- [ ] **Step 2: Commit**

```bash
git add plugins/devteam/.claude-plugin/plugin.json
git commit -m "chore(devteam): bump version 1.0.1 → 1.1.0"
```

---

## Task 13: Update CHANGELOG.md

**Files:**
- Modify: `plugins/devteam/CHANGELOG.md`

- [ ] **Step 1: Read current CHANGELOG to see existing format**

```bash
head -30 plugins/devteam/CHANGELOG.md
```

- [ ] **Step 2: Prepend a new entry at the top (after any header) matching existing format**

The entry must include the four bullet groups below. Use the same heading depth and date format the existing entries use.

```markdown
## [1.1.0] — 2026-05-30

### Added
- `/save [name?]` — capture session state as a curated savepoint at `~/.claude/devteam/saves/<slug>/latest.md` with optional decisions sidecar. Layered design (~1500 tokens main + ~3000 tokens sidecar on demand), enforced size caps, rolling 10-entry history, named save slots.
- `/continue [name|latest|list?]` — resume from a savepoint; subsumes the prior `/lead-resume` by surfacing any pending `WAITING ON USER` block and offering to answer it inline.
- `hooks/save-autosave.sh` — Stop + SessionEnd hook with change-based gating (writes only when git HEAD or slack mtime changes) and 10-minute clobber protection against fresh explicit saves. Prints `📦 autosaved` on write.
- `hooks/save-reminder.sh` — Stop hook mirroring handoff's pattern: nags once per session when commits land without a `/save` since `.last-explicit` marker.
- `hooks/session-start.sh` — extended to surface existing saves on session entry (`📌 Save exists for this project ...`).

### Removed
- `/lead-resume` — functionality folded into `/continue` (which auto-surfaces pending blocks).
- `/lead-abort` — functionality folded into `/save` (saving is the gravestone; no consumer left for `.last-phase=aborted`).

### Changed
- `/lead-setup` now registers Stop and SessionEnd hooks in addition to SessionStart. Existing setups remain idempotent — re-running picks up the new hook registrations.
- `.claude-plugin/plugin.json` version bumped 1.0.1 → 1.1.0.

### Migration notes
- Existing devteam users: run `/lead-setup` to register the new hooks (idempotent).
- claude-sync users on `/handoff` and `/continue-work`: those still work; deprecation lands in claude-sync after a 2-week / 15-session validation period with the new devteam commands (Phase 4).
```

- [ ] **Step 3: Commit**

```bash
git add plugins/devteam/CHANGELOG.md
git commit -m "docs(devteam): CHANGELOG entry for 1.1.0 (save/continue + hooks)"
```

---

## Task 14: Update README.md commands table

**Files:**
- Modify: `plugins/devteam/README.md`

- [ ] **Step 1: Find the commands table**

```bash
grep -n "lead-resume\|lead-abort\|## Commands\|| Command" plugins/devteam/README.md
```

- [ ] **Step 2: Remove `/lead-resume` and `/lead-abort` rows from the commands table and add `/save` and `/continue` rows**

Locate the commands table (likely under `## Commands` or `## Command reference`). Remove the rows for `/lead-resume` and `/lead-abort`. Add these rows (insert near the lead-* group, or in alphabetical order — match the table's existing convention):

```markdown
| `/save [name?]` | save skill | Capture session state as a curated savepoint at `~/.claude/devteam/saves/<slug>/`. Optional `<name>` pins to `named/<name>.md`. |
| `/continue [arg?]` | continue skill | Resume from a savepoint. Forms: `latest` (default), `list` (menu), `<name>` (named/history lookup), `--with-decisions` (load sidecar). |
```

Also locate any prose paragraphs mentioning `/lead-resume` or `/lead-abort` (especially in setup/usage sections) and update them to reference `/save` and `/continue` instead.

- [ ] **Step 3: Verify no stray references remain**

```bash
grep -n "lead-resume\|lead-abort" plugins/devteam/README.md
```

Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add plugins/devteam/README.md
git commit -m "docs(devteam): update README commands table for save/continue, remove lead-resume/abort"
```

---

## Task 15: Update ARCHITECTURE.md persistence section

**Files:**
- Modify: `plugins/devteam/ARCHITECTURE.md`

- [ ] **Step 1: Find the persistence section**

```bash
grep -n "## Persistence\|## Why some original" plugins/devteam/ARCHITECTURE.md
```

- [ ] **Step 2: Append to the "Persistence model" section**

After the existing "Cross-session memory is handled separately via..." paragraph, add:

```markdown

**Cross-session resume** is handled by `/save` and `/continue` (added in 1.1.0). Saves live at `~/.claude/devteam/saves/<slug>/` — the third leg of the global-tier persistence (alongside `memory/` lessons and `conventions/` stack guidance). Saves are layered (minimal `latest.md` + optional `latest-decisions.md` sidecar) with enforced size caps and rolling 10-entry history per project. A change-based Stop autosave hook protects against crashes between explicit saves.
```

- [ ] **Step 3: Update the "Why some original ideas were dropped" section**

Append a new subsection at the end:

```markdown

**`/lead-resume` and `/lead-abort` as separate commands.** Both were narrowly scoped: `/lead-resume` only handled the WAITING-ON-USER block case; `/lead-abort` only set a `.last-phase=aborted` marker no one consumed. Once `/save` + `/continue` arrived in 1.1.0, both became redundant — `/continue` surfaces pending blocks automatically, and `/save` IS the abort artifact (you save state and walk away). Removed in 1.1.0.
```

- [ ] **Step 4: Commit**

```bash
git add plugins/devteam/ARCHITECTURE.md
git commit -m "docs(devteam): document save/continue persistence + lead-resume/abort removal in ARCHITECTURE"
```

---

## Task 16: Update docs/state-files.md global table

**Files:**
- Modify: `plugins/devteam/docs/state-files.md`

- [ ] **Step 1: Find the global table**

```bash
grep -n "Global\|~/.claude/devteam" plugins/devteam/docs/state-files.md
```

- [ ] **Step 2: Add a row for `saves/<slug>/` under the global table**

In the `## Global (~/.claude/devteam/)` table, add this row (insert before or after `projects/` to fit alphabetical/logical order):

```markdown
| `saves/<slug>/latest.md` | `/save` skill + `save-autosave.sh` hook | Current curated session save (overwritten each save). Layered: optional `latest-decisions.md` sidecar; rolling `history/` (10 retained); permanent `named/`. |
```

- [ ] **Step 3: Commit**

```bash
git add plugins/devteam/docs/state-files.md
git commit -m "docs(devteam): add saves/ to state-files.md global table"
```

---

## Task 17: Add `/.claude/devteam/saves/` to claude-sync .gitignore

**Files:**
- Modify: `claude-sync/.gitignore` (in the user's claude-sync repo, NOT in devteam)

- [ ] **Step 1: Locate claude-sync repo**

```bash
ls /Users/brian/Desktop/claude-projects/claude-sync/.gitignore
```

- [ ] **Step 2: Append the saves directory to .gitignore**

If `.gitignore` exists, append the line below (check for existing entry first):

```
# devteam savepoints — machine-local, autosaves are too noisy for git history
/.claude/devteam/saves/
```

If the line is already present: no-op.

- [ ] **Step 3: Commit in claude-sync repo**

```bash
cd /Users/brian/Desktop/claude-projects/claude-sync
git add .gitignore
git commit -m "chore: gitignore devteam saves (machine-local, autosave noise)"
cd -
```

---

## Task 18: Final integration verification

**Files:**
- (no edits — manual verification)

- [ ] **Step 1: Re-run all shell tests**

```bash
./plugins/devteam/bin/test-save-autosave.sh
./plugins/devteam/bin/test-save-reminder.sh
```

Both should print `OK: all ... smoke tests passed`.

- [ ] **Step 2: Lint-check the bin scripts**

```bash
sh -n plugins/devteam/hooks/save-autosave.sh
sh -n plugins/devteam/hooks/save-reminder.sh
sh -n plugins/devteam/hooks/session-start.sh
```

Expected: no output (syntax OK).

- [ ] **Step 3: Verify file inventory matches the spec**

```bash
ls plugins/devteam/skills/save/SKILL.md \
   plugins/devteam/skills/continue/SKILL.md \
   plugins/devteam/commands/save.md \
   plugins/devteam/commands/continue.md \
   plugins/devteam/hooks/save-autosave.sh \
   plugins/devteam/hooks/save-reminder.sh \
   plugins/devteam/bin/test-save-autosave.sh \
   plugins/devteam/bin/test-save-reminder.sh
ls plugins/devteam/commands/lead-resume.md plugins/devteam/commands/lead-abort.md 2>&1 | grep "No such"
```

Expected: first `ls` lists all 8 files; second confirms both old commands are gone.

- [ ] **Step 4: Verify plugin.json version**

```bash
grep '"version"' plugins/devteam/.claude-plugin/plugin.json
```

Expected: `"version": "1.1.0",`

- [ ] **Step 5: Verify no stale references to removed commands**

```bash
grep -rn "lead-resume\|lead-abort" plugins/devteam/ --exclude-dir=.git --exclude="*CHANGELOG*" --exclude="*ARCHITECTURE*"
```

Expected: no output (CHANGELOG and ARCHITECTURE legitimately reference the removed commands in their entries; everything else should be clean).

- [ ] **Step 6: Final commit if any cleanup happened**

```bash
git status
# if anything to add:
git add -A plugins/devteam/
git commit -m "chore(devteam): cleanup stale references post-1.1.0"
```

---

## Out of scope (for follow-up plans)

The following items from the spec are intentionally NOT in this plan; they belong to later sub-projects in the broader "Claude brain" roadmap:

- Cross-machine sync of saves (Obsidian vault on Google Drive)
- Claude.ai web bridge via remote MCP
- Persistent identity layer (SOUL.md / IDENTITY.md)
- Semantic memory store
- One-command bootstrap
- Phase 2 (live-use validation): user runs `/save` + `/continue` in daily flow for ~2 weeks / 15 sessions
- Phase 3: claude-sync setup script requires devteam
- Phase 4: delete claude-sync handoff/continue-work + remove handoff Stop-hook entry from ~/.claude/settings.json

Once Phase 2 confidence is reached, a Phase 3+4 follow-up plan will handle claude-sync changes and settings.json cleanup.
