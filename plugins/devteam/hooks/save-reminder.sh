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
