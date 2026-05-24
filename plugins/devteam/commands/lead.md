---
description: LEAD mode — full team orchestration. Classifies a task, dispatches specialists, funnels questions, reports.
---

The user invoked `/lead` with: $ARGUMENTS

1. Parse $ARGUMENTS for flags (`--tier`, `--mode`, `--notify`, `--no-notify`, `--from`, `--dry-run`, `--model`) and the task string.
2. If `--model <name>` was passed: validate `<name>` is one of `sonnet`, `opus`, `haiku`. If invalid, refuse with usage message: `--model must be one of: sonnet, opus, haiku`. If valid, write to `.devteam/state/.flags` (one `key=value` per line — append or overwrite the `model=` line). LEAD applies this override to every worker dispatch (workers only — skills run in main thread and inherit the user's session model). See `skills/lead/SKILL.md` §5.5 for the propagation rules.
3. If `--no-state` was passed: refuse with explanation (`/lead` requires state; use a direct specialist command for ephemeral runs).
4. If `--from <phase>` was passed: validate the phase's prerequisites exist in `.devteam/state/`; if not, prompt user to back-fill or reject.
5. Invoke the `lead` skill with the parsed inputs.
6. The `lead` skill handles: dependency check, classification, dispatch loop, funnel, reporting.
