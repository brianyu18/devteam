---
description: Capture the current session's state as a savepoint for cross-session continuity. Optional <name> arg pins the checkpoint to ~/.claude/devteam/checkpoints/<slug>/named/ (never rotated). Without args, an auto-generated kebab-slug name + readable description are produced.
---

The user invoked `/checkpoint` with: $ARGUMENTS

Invoke the `checkpoint` skill. Pass `$ARGUMENTS` as the optional `<name>` if present.

If no `$ARGUMENTS`, you generate the name + description from session context per the skill spec.
