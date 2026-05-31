---
name: checkpoint
description: Use to capture the current session's state to disk as a checkpoint, so a future session can resume with minimal context loss. Invoked directly via /checkpoint [name?], or self-invoked when the model detects user intent to end the session ("wrapping up", "have to go", etc.) after asking the user for consent.
---

# CHECKPOINT

You own the CHECKPOINT action. Capture the current session's state into a curated checkpoint at `~/.claude/devteam/checkpoints/<slug>/`.

## When to invoke

- User typed `/checkpoint` (explicit)
- User typed `/checkpoint <name>` (explicit with override name)
- You detected end-of-session intent in conversation ("wrapping up", "have to go", "talk later", "let's continue tomorrow", "see you", "good night", "lunch break", "EOD", "done for today") AND user confirmed via "Want me to checkpoint before you go? [Y/n]" → yes

Never auto-checkpoint silently on intent. Always ask first.

## Inputs

- `<name>` arg if provided (else auto-generate kebab-slug + readable description)
- `.devteam/state/` if it exists (project name, .last-phase, slack tail, pending blocks, build/review/test status files)
- `git` (branch, HEAD, last 5 commits)
- Current conversation context (your job to synthesize goal / where left off / next steps / blockers / decisions)

## Steps

1. **Resolve paths.**
   ```sh
   SLUG=$(pwd | sed 's|/|-|g')
   DIR="$HOME/.claude/devteam/checkpoints/$SLUG"
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

9. **Touch `.last-explicit` marker** (consumed by checkpoint-reminder.sh):
   ```sh
   date +%s > "$DIR/.last-explicit"
   ```

10. **If `.devteam/state/` exists**, append a SUMMARY entry to slack:
    ```sh
    "$PLUGIN_PATH/bin/slack-append.sh" "[CHECKPOINT#] INFO  checkpoint written: <name>"
    ```

11. **Report to user:**
    ```
    CHECKPOINT WRITTEN
    ══════════════════
    Project:    <project>
    Name:       <name>
    Latest:     <path> (<token-count> tokens)
    Decisions:  +N (sidecar written, K tokens)   # only if has_decisions
    History:    N checkpoints retained
    ```

## Frontmatter contract

Always include in `latest.md` frontmatter:
- `slug`, `project`, `phase`, `saved_at` (UTC ISO-8601), `saved_by` (explicit | intent), `session_id`, `name`, `description`, `git_branch`, `git_head`, `has_decisions`
