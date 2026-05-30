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
