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
