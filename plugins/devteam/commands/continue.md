---
description: Resume a prior session from a savepoint. Forms: /continue (load latest), /continue list (menu), /continue <name> (load named or history match), /continue --with-decisions (load latest + decisions sidecar).
---

The user invoked `/continue` with: $ARGUMENTS

Invoke the `continue` skill. Pass `$ARGUMENTS` verbatim — the skill resolves keywords (`latest`, `list`, `--with-decisions`) and treats any other non-empty arg as a `<name>` lookup.
