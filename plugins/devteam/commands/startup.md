---
description: Run a project on full autopilot from a goal — autonomous THINK→DESIGN→PLAN→BUILD→REVIEW→TEST using council-lite for decisions, tapping you only on escalation gates, stopping at the ship boundary. Invokes the startup skill.
---

The user invoked `/startup` with: $ARGUMENTS

1. Parse `$ARGUMENTS` for flags and the goal string:
   - `--budget <N>` — max subagent dispatches this run (default 40). Validate positive integer.
   - `--fanout <K>` — max parallel subagents per wave (default 4). Validate positive integer.
   - `--tier <t>` — override classification (`simple|bug|feature|complex`). Default: auto-classify, minimum `feature`.
   - `--ship` — allow the SHIP phase to run (push/deploy still confirms).
   - `--no-images` — force presto `--nogen` (skip all paid image generation).
   - `--notify` / `--no-notify` — PushNotification on a stranded gate (default on).
   - `--goal-file <path>` — read the goal brief from a file.
   - Everything not a flag is the goal. If the goal is empty and no `--goal-file` is given, ask the user what to build and stop.
2. Resolve the plugin install path: read `.devteam/state/.plugin-path` if present, else use `${CLAUDE_PLUGIN_ROOT}` and write it (create `.devteam/state/` if needed).
3. Invoke the `startup` skill with the goal, the parsed flags, and the resolved plugin path.
4. The `startup` skill handles: the contract (one approval), the autonomous phase loop, council-lite decisions, the escalation gates, interrupt/steering, and the ship-boundary stop.
5. Autopilot forces autonomous mode for the run and restores the prior mode on exit.
