#!/bin/sh
# Smoke test for checkpoint-reminder.sh
# Covers: silent when no .last-explicit, prints when commits exceed last-explicit,
# silent on re-fire within same session (marker).
set -eu

TMPROOT=$(mktemp -d)
export DEVTEAM_CHECKPOINTS_HOME="$TMPROOT/checkpoints"
export HOME="$TMPROOT/home"
export CLAUDE_SESSION_ID="test-session-$$"
mkdir -p "$DEVTEAM_CHECKPOINTS_HOME"
cd "$TMPROOT"
git init -q .
git -c user.email=t@t -c user.name=t commit --allow-empty -q -m "seed"

HELPER="$OLDPWD/plugins/devteam/hooks/checkpoint-reminder.sh"
[ -x "$HELPER" ] || { echo "FAIL: hook not executable: $HELPER"; exit 1; }

SLUG=$(echo "$TMPROOT" | sed 's|/|-|g')
DIR="$DEVTEAM_CHECKPOINTS_HOME/$SLUG"
mkdir -p "$DIR"

# 1. Silent when .last-explicit doesn't exist
OUT=$("$HELPER" 2>&1 || true)
[ -z "$OUT" ] || { echo "FAIL: expected silent (no last-explicit), got: $OUT"; exit 1; }

# 2. Set last-explicit 1 hour ago, make a commit, expect nag
date -u -v-1H +%s > "$DIR/.last-explicit" 2>/dev/null || date -u -d "1 hour ago" +%s > "$DIR/.last-explicit"
git -c user.email=t@t -c user.name=t commit --allow-empty -q -m "new commit"
OUT=$("$HELPER" 2>&1 || true)
echo "$OUT" | grep -q "/checkpoint reminder" || { echo "FAIL: expected /checkpoint reminder, got: $OUT"; exit 1; }

# 3. Re-fire in same session → silent (marker rate-limit)
OUT2=$("$HELPER" 2>&1 || true)
[ -z "$OUT2" ] || { echo "FAIL: expected silent on re-fire same session, got: $OUT2"; exit 1; }

echo "OK: all checkpoint-reminder smoke tests passed"
rm -rf "$TMPROOT"
