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
