---
description: Convene the deliberation council on a question, decision, or proposal. Dispatches neutral investigators, pro/con advocates, proposal reviewers, and a mandatory synthesizer; returns one reasoned verdict. Invokes the council skill.
---

The user invoked `/council` with: $ARGUMENTS

1. Parse `$ARGUMENTS` for flags and the proposition string:
   - `--lite` — trim the roster to 1 investigator + 1 pro + 1 con + 1 reviewer + synthesizer (no divergent explorer).
   - `--model <name>` — override all members; validate `<name>` ∈ {sonnet, opus, haiku}. If invalid, refuse with: `--model must be one of: sonnet, opus, haiku`.
   - `--diff <ref>` — force code-mode against the given git range.
   - `--no-divergent` — skip the optional divergent explorer.
   - Everything not a flag is the proposition. If the proposition is empty, ask the user what to deliberate on and stop.
2. Resolve the plugin install path:
   - If `.devteam/state/.plugin-path` exists, read it.
   - Else use `${CLAUDE_PLUGIN_ROOT}`. If `.devteam/state/` exists but `.plugin-path` does not, write `${CLAUDE_PLUGIN_ROOT}` to `.devteam/state/.plugin-path`.
3. Invoke the `council` skill with: the proposition, the parsed flags, and the resolved plugin path.
4. The `council` skill handles: intake + mode detection, the 3-wave dispatch, synthesis, and verdict delivery.
5. The council is ephemeral by default. It writes to `.devteam/state/` (slack + `council.md`) ONLY if that directory already exists.
