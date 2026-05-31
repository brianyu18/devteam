# `.devteam/` state file reference

LEAD and specialists read/write these files. This document is the contract.

## Per-repo state (`.devteam/state/`)

| File | Writer | Purpose |
|---|---|---|
| `slack.md` | All actors (via `bin/slack-append.sh`) | Chronological audit log, append-only |
| `slack-detail/<id>.md` | Whoever creates the entry | Optional deep record for one slack entry |
| `archive/slack-<date>.md` | LEAD (on rotation) | Archived slack pieces (>2000 lines / 200 KB) |
| `.project-name` | LEAD | Project slug used for archive filename |
| `.last-phase` | LEAD | Last completed phase name |
| `.plugin-path` | LEAD (on startup) | Absolute path to devteam plugin install dir |
| `.started-in` | First specialist invoked | `lead` or `direct` |
| `.flags` | LEAD (when user passes flags like `--model`) | Run-level flags as `key=value` lines (e.g., `model=opus`). Read by LEAD at boot; applied during worker dispatch. See `skills/lead/SKILL.md` §5.5. |
| `think.md` | THINKER | THINK phase output |
| `plan.md` | PLANNER | Final plan |
| `plan-partitions.md` | PLANNER | YAML partition map BUILD consumes |
| `plan-critiques/{eng,lead,design,devex}.md` | PLANNER (via gstack /plan-*-review) | Parallel critique outputs (note: `lead.md` is produced by gstack `/plan-ceo-review` — gstack command name preserved per HANDOFF) |
| `build-progress.md` | LEAD | Per-partition status (human-readable handover) |
| `build-status.json` | LEAD | Per-partition status (machine-readable) |
| `review-findings.json` | LEAD | Merged findings array |
| `test-results.json` | LEAD | Per-suite pass/fail + coverage |
| `ship-log.md` | SHIPPER | Sequential ship-action log |
| `project-type.md` | SHIPPER (on first SHIP) | Project type detection result |
| `reflect.md` | REFLECTOR | REFLECT phase output |

## Per-repo mode

| File | Purpose |
|---|---|
| `.devteam/mode` | `work-together` or `autonomous` |
| `.devteam/slack.lock.d/` | mkdir-mutex directory used by `bin/slack-append.sh` |

## Global (`~/.claude/devteam/`)

| Path | Writer | Purpose |
|---|---|---|
| `memory/MEMORY.md` | REFLECTOR | Index of cross-project memory files |
| `memory/<topic>.md` | REFLECTOR | One file per topic |
| `conventions/index.json` | seed / user | Detection signals → convention file paths |
| `conventions/<domain>/<stack>.md` | seed / user | Per-stack guidance loaded by BUILDER briefs |
| `projects/<slug>-<date>.md` | LEAD | Archived completed project |
| `checkpoints/<slug>/latest.md` | `/checkpoint` skill + `checkpoint-autosave.sh` hook | Current curated session recovery checkpoint (overwritten each save). Layered: optional `latest-decisions.md` sidecar; rolling `history/` (10 retained); permanent `named/`. |
