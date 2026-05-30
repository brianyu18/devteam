---
description: Capture the current session's state as a savepoint for cross-session continuity. Optional <name> arg pins the save to ~/.claude/devteam/saves/<slug>/named/ (never rotated). Without args, an auto-generated kebab-slug name + readable description are produced.
---

The user invoked `/save` with: $ARGUMENTS

Invoke the `save` skill. Pass `$ARGUMENTS` as the optional `<name>` if present.

If no `$ARGUMENTS`, you generate the name + description from session context per the skill spec.
