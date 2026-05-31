# devteam

## devteam — Multi-Agent Dev Team in a Box

A virtual dev team living inside Claude Code. You talk to **LEAD**; LEAD dispatches a roster of specialist subagents across 7 sprint phases (THINK / PLAN / BUILD / REVIEW / TEST / SHIP / REFLECT) with parallel fan-out, structured artifact handoffs, and an append-only "team slack" audit log per project.

**v1.0.0** — rename from `toolbox`. Clean break; see [Migration from toolbox 0.1.0](#13-migration-from-toolbox-010).

---

## Architecture

The plugin models a small dev team. You are the product owner. **LEAD** is your tech lead and only point of contact. LEAD reads your task, classifies it (simple / bug / feature / complex), picks the right phase subset, then directly dispatches workers as Task-tool subagents in parallel.

```
You (user)
  ↓
LEAD  (skill — your only interface in /lead mode)
  ↓ Task tool — dispatches directly
  ├── THINKER      (skill — THINK phase)
  ├── PLANNER      (skill — PLAN phase)
  ├── BUILDER ×N   (agent — BUILD, one per partition, parallel)
  ├── review-specialist ×M  (agent — REVIEW, one per lens, parallel)
  ├── TESTER       (agent — TEST)
  ├── SHIPPER      (skill — SHIP phase)
  ├── REFLECTOR    (skill — REFLECT phase)
  └── Utility: EXPLORER, CRITIC, SYNTHESIZER, INVESTIGATOR
```

**Why no lead agents?** Early design included BUILD-LEAD, REVIEW-LEAD, and TEST-LEAD as middleware coordinators between LEAD and the workers. A1-final removed them: subagents cannot dispatch nested subagents in Claude Code's current execution model, so these roles were vestigial. LEAD dispatches workers directly. This also simplifies the dispatch graph and removes a latency hop.

**The skill-vs-agent rule.** Dialogue with the user → skill (keeps context, can AskUserQuestion). Heads-down or parallelizable work → agent (fresh context, parallel-capable). Skills can dispatch agents internally; agents return packets to whoever dispatched them.

**The funnel rule.** Workers never call AskUserQuestion in `/lead` mode. They return a `blocked` packet to LEAD. LEAD presents the question with two recommendations (specialist's + LEAD's own). In direct mode (`/think`, `/plan`, etc.), this rule does not apply.

---

## Quick Start

```bash
# 1. Install (uninstall old toolbox first if present)
/plugin marketplace add brianyu18/devteam
/plugin install devteam@devteam

# 2. One-time setup — registers SessionStart hook + seeds conventions library
/lead-setup

# 3. Go
/lead "add dark mode toggle to the settings page"
```

LEAD will classify the task, run the appropriate phase subset, check in at each boundary (Work-Together mode), and produce a final report. State is written to `.devteam/state/` in your project directory.

Add `.devteam/` to your project's `.gitignore` — devteam won't do it automatically.

```
# Recommended
.devteam/
```

---

## Two Ways to Invoke

### LEAD mode (default)

```bash
/lead "task description"
/lead --tier complex "rebuild the auth system"
/lead --mode autonomous "fix the flaky CI test"
```

LEAD orchestrates all phases. You interact only with LEAD. Workers are invisible unless you ask LEAD to show its work. State and slack are written. Resume/abort available at any time.

### Direct mode

```bash
/think "explore caching strategies"
/plan "new notification system"
/build "implement dark mode toggle"
/review-project
/test integration
/ship-project
/reflect
```

Any specialist can be invoked standalone for ad-hoc use without booting the whole team. Direct mode still writes to `.devteam/state/slack.md` (with a `started_in: direct` marker), so LEAD sees the work next time it runs. Use `--no-state` to skip writes entirely.

---

## The Team

### Skills (5) — dialogue roles

| Skill | Path | Owns |
|---|---|---|
| LEAD | `skills/lead/SKILL.md` | Classification, dispatch, funnel, autonomy, final report |
| THINKER | `skills/thinker/SKILL.md` | THINK phase — brainstorming via `superpowers:brainstorming` |
| PLANNER | `skills/planner/SKILL.md` | PLAN phase — partition plan, critique fan-out via `gstack:/plan-*-review` |
| SHIPPER | `skills/shipper/SKILL.md` | SHIP phase — project-type-aware deploy via `gstack:/ship` chain |
| REFLECTOR | `skills/reflector/SKILL.md` | REFLECT phase — tier-gated retros + watchlist integration |

### Worker agents (7) — heads-down / parallel

| Agent | Path | Role |
|---|---|---|
| BUILDER | `agents/builder.md` | Implements one code partition (TDD; one per partition, parallel) |
| review-specialist | `agents/review-specialist.md` | Runs one review lens (dispatched per applicable lens, parallel) |
| TESTER | `agents/tester.md` | Runs one test layer; returns results JSON |
| EXPLORER | `agents/explorer.md` | Divergent generation — produces N framings or options |
| CRITIC | `agents/critic.md` | Adversarial critique — finds flaws in a draft |
| SYNTHESIZER | `agents/synthesizer.md` | Merges N inputs into one coherent output |
| INVESTIGATOR | `agents/investigator.md` | Read-only research — finds usage, explains code |

### Review lenses (6) — loaded by review-specialist

Located in `agents/review-lenses/`. LEAD selects applicable lenses via `bin/devteam-pick-lenses.sh` (deterministic regex over `git diff --name-only`):

- `security.md` — auth, XSS, SQLi, secrets, OWASP
- `perf.md` — query patterns, render perf, bundle size, hot paths
- `testing.md` — coverage gaps, flaky patterns, missing edge cases
- `a11y.md` — keyboard nav, screen reader, contrast, semantic HTML
- `data-migration.md` — migration safety, rollback, zero-downtime patterns
- `api-contract.md` — breaking changes, versioning, schema drift

---

## The 7 Phases

| Phase | Who runs it | What happens | Artifact |
|---|---|---|---|
| THINK | THINKER skill | Explores problem space; generates framings and risks; optionally runs `EXPLORER ×3` in shotgun mode | `state/think.md` |
| PLAN | PLANNER skill | Writes plan, partitions work into parallel-safe BUILDs with dependencies; fans out plan critiques via gstack | `state/plan.md`, `state/plan-partitions.md`, `state/plan-critiques/` |
| BUILD | BUILDER agents | Implements partitions in parallel waves based on `plan-partitions.md`; TDD; one agent per partition | Code committed, `state/build-progress.md`, `state/build-status.json` |
| REVIEW | review-specialist agents | Parallel lens review; each specialist is read-only, reports JSON findings; lens selection by `bin/devteam-pick-lenses.sh` | `state/review-findings.json` |
| TEST | TESTER agent | Detects test layers via `bin/devteam-detect-stack.sh --tests`; runs each layer; aggregates results | `state/test-results.json` |
| SHIP | SHIPPER skill | Detects project type (web/plugin/library/cli/static); chains `gstack:/ship → /land-and-deploy → /canary` | `state/ship-log.md`, updated VERSION/CHANGELOG, tag, PR |
| REFLECT | REFLECTOR skill | Tier-gated retro (skip for simple; focused for bug; light for feature; full for complex); analyzes slack for watchlist signals | `state/reflect.md`, appended to `~/.claude/devteam/memory/` |

LEAD picks a phase subset based on task tier:
- **simple** → BUILD + TEST (verify)
- **bug** → THINK (lite) + BUILD + TEST + REVIEW
- **feature** → THINK + PLAN + BUILD + REVIEW + TEST + SHIP
- **complex** → all 7 phases, parallel BUILD fan-out per wave

---

## Modes

### Two axes

**Invocation mode** — how you engage (LEAD or direct specialist). Chosen per invocation.

**Autonomy mode** — how much LEAD checks in. Persisted in `.devteam/mode`. Default: `work-together`.

### Work-Together (default)

LEAD checks in at every decision point:

- Before each phase boundary
- When any specialist returns a blocked question packet (always funneled with two recommendations)
- Before any destructive action (push, deploy, rm, drop table, force-push)

### Autonomous

LEAD uses its best judgment:

- Classifies silently (mentions in opening)
- Phase transitions without check-ins
- Pre-flights blocked questions using CRITIC + EXPLORER; answers if confident; halts cleanly with PushNotification if still ambiguous

### Switching modes

```bash
# Persistent
/lead-mode autonomous
/lead-mode work-together

# This run only
/lead --mode autonomous "task"

# Natural language (inside LEAD session)
"go autonomous" / "check in with me from now on"
```

Mid-flight switches happen at the next safe point and are logged to slack as a `MODE` entry.

### Hard rules (both modes)

- Destructive actions always confirm.
- Twice-failed specialist always escalates to user.

---

## Team Slack

Every actor — LEAD, every skill, every agent — appends one-line entries to `.devteam/state/slack.md`. This is the chronological audit log for the project.

### Format

```
#YY-MM-DD-HH-MM-SS  YYYY-MM-DD HH:MM:SS  [ACTOR#NN]  SEVERITY  one-line description
                                                                  → detail: slack-detail/<id>.md
```

### Severity tags

`INFO` | `DECISION` | `QUESTION` | `ANSWER` | `FUNNEL` | `BLOCKER` | `DESTRUCTIVE` | `DONE` | `ERROR` | `MODE` | `SUMMARY` | `WATCHLIST`

`WATCHLIST` entries feed `bin/devteam-watchlist.sh` — see [WATCHLIST.md](WATCHLIST.md) for signal thresholds.

### Race safety

Multiple parallel agents writing to the same file at the same time. `bin/slack-append.sh` uses a `mkdir`-mutex (`slack.lock.d/`) — POSIX-portable, no `flock` dependency. Stale locks (from crashed processes) are detected and cleared. Per-actor counters in `[ACTOR#NN]` ensure collision-free IDs without millisecond precision (BSD `date` doesn't support `%3N`).

### Rotation

At 2000 lines / 200 KB, slack auto-archives to `.devteam/state/archive/slack-<date>.md` while preserving the in-progress phase.

### Viewing

```bash
/lead-show-slack           # full log
/lead-show-slack PLAN      # filter by phase
/lead-show-slack --decisions  # DECISION entries only
```

---

## State / Memory / Conventions

### Per-project state (`.devteam/`)

```
.devteam/
├── mode                         # work-together | autonomous
├── slack.lock.d/                # mkdir-mutex (transient)
└── state/
    ├── slack.md                 # audit log
    ├── slack-detail/            # optional deep records per entry
    ├── archive/                 # rotated slack
    ├── .project-name            # LEAD-managed
    ├── .last-phase              # updated after each phase
    ├── .plugin-path             # absolute install path (used in subagent briefs)
    ├── .started-in              # "lead" | "direct"
    ├── think.md
    ├── plan.md
    ├── plan-partitions.md
    ├── plan-critiques/{eng,ceo,design,devex}.md
    ├── build-progress.md
    ├── build-status.json
    ├── review-findings.json
    ├── test-results.json
    ├── ship-log.md
    ├── project-type.md
    └── reflect.md
```

### Global memory (`~/.claude/devteam/memory/`)

REFLECTOR appends lessons to `MEMORY.md` after each project. LEAD reads this at startup to carry preferences and patterns across projects.

### Conventions library (`~/.claude/devteam/conventions/`)

Stack-specific coding conventions. Seeded from `conventions-seed/` on `/lead-setup`. LEAD detects the active stack via `bin/devteam-detect-stack.sh` and injects the matching convention file into each BUILDER's brief.

8 stacks seeded:
- `languages/pinescript.md` — Pine Script v5 indicators
- `languages/claude-code-plugin.md` — Claude Code plugin authoring
- `frontend/react.md` — React components and hooks
- `frontend/tailwind.md` — Tailwind CSS
- `frontend/nextjs.md` — Next.js App Router
- `backend/node.md` — Node.js server patterns
- `backend/supabase.md` — Supabase (Auth, DB, Storage, Realtime)
- `db/postgres.md` — PostgreSQL query and migration patterns

Edit files in `~/.claude/devteam/conventions/` to add your own conventions. See `conventions-seed/README.md` for the standard section format. The seed files in the plugin are overwritten on upgrade; your copies in `~/.claude/` are preserved.

### Completed project archive (`~/.claude/devteam/projects/`)

On user confirmation after a project completes, LEAD archives the full slack to `~/.claude/devteam/projects/<slug>-<date>.md` and clears `.devteam/state/`.

---

## Command Reference

19 commands total (7 LEAD-management + 7 specialists + 5 deprecated aliases).

### LEAD management

| Command | Description |
|---|---|
| `/lead [task]` | Invoke LEAD. Full team orchestration. |
| `/lead-status` | Show current project state, last phase, mode. Read-only. |
| `/lead-mode <name>` | Set autonomy mode persistently. `work-together` or `autonomous`. |
| `/lead-show-slack [phase] [--decisions]` | Read team slack with optional filters. |
| `/checkpoint [name?]` | Per-session recovery checkpoint at `~/.claude/devteam/checkpoints/<slug>/`. Optional `<name>` pins to `named/<name>.md`. Rolling history of 10 + named slots. Companion to `/continue`. |
| `/continue [arg?]` | Resume from a savepoint. Forms: `latest` (default), `list` (menu), `<name>` (named/history lookup), `--with-decisions` (load sidecar). |
| `/lead-setup` | One-time setup: register SessionStart hook + seed conventions library. |

### Specialist commands (direct mode)

| Command | Specialist | Notes |
|---|---|---|
| `/think [task]` | THINKER | Direct THINK phase |
| `/plan [task]` | PLANNER | Direct PLAN phase |
| `/build [task]` | BUILDER(s) | `--parallel` to fan out |
| `/review-project [path]` | review-specialist(s) | Renamed to avoid gstack `/review` collision |
| `/test [layer]` | TESTER | Run one test layer |
| `/ship-project` | SHIPPER | Renamed to avoid gstack `/ship` collision |
| `/reflect` | REFLECTOR | Direct REFLECT phase |

### Deprecated aliases (toolbox 0.1.0 backward compat)

All route to `/lead` with the appropriate `--tier` flag. Will be removed in 2.0.0.

| Command | Routes to |
|---|---|
| `/toolbox` | `/lead` |
| `/toolbox-simple` | `/lead --tier simple` |
| `/toolbox-bug` | `/lead --tier bug` |
| `/toolbox-feature` | `/lead --tier feature` |
| `/toolbox-complex` | `/lead --tier complex` |

### Flags

| Flag | Effect |
|---|---|
| `--tier <name>` | Force tier classification (simple / bug / feature / complex) |
| `--mode <name>` | Set autonomy mode for this run only |
| `--notify` / `--no-notify` | Override notification default |
| `--parallel` | Force parallel fan-out (direct `/build`, `/review-project`, `/test`) |
| `--no-state` | Ephemeral run — no slack or state writes (direct mode only) |
| `--from <phase>` | Resume from a specific phase; validates prerequisites |
| `--dry-run` | Print dispatch intent without executing |

---

## How `/checkpoint` relates to brain `/save`

devteam's `/checkpoint` and the brain layer's `/save` (in a personal Obsidian vault — see [shared-brain](#)) are complementary, not redundant. Pick by intent:

| Use `/checkpoint` (devteam) when… | Use `/save` (brain) when… |
|---|---|
| You want a recovery point in *this* session (many per session) | You want to update the project's canonical state (one per project lifecycle) |
| Need rolling history + crash insurance | Need cross-machine, cross-tool source of truth |
| Local to this machine | Synced via vault + Drive to all your devices and AI tools |
| Public devteam users — anyone with the plugin has this | Personal (requires your shared-brain vault setup) |
| "Stash this attempt, I might try another" | "Update where this project is, across my whole life" |

If you have both layers set up, `/fullsave` (a user-personal skill in claude-sync) invokes `/checkpoint` + `/save` + `/log` together at natural end-of-session moments.

---

## Customizing

### Override conventions

Edit (or add) files in `~/.claude/devteam/conventions/`. These are your copies — never overwritten by plugin upgrades. See `conventions-seed/README.md` for the standard section format (Stack overview / Conventions / Anti-patterns / Test patterns / Common pitfalls / References).

To add a new stack:
1. Drop a `.md` file in the right folder under `~/.claude/devteam/conventions/`.
2. Add a detection signal entry to `~/.claude/devteam/conventions/index.json` (see existing entries for the `{"file_exists": ...}` or `{"file_contains": ...}` signal format).
3. `bin/devteam-detect-stack.sh` will pick it up automatically.

### Autonomy mode

Set default mode at project start: `/lead-mode autonomous` or `/lead-mode work-together`.

### Hook customization

The SessionStart hook (`hooks/session-start.sh`) shows active project status when you open a repo. Edit `~/.claude/settings.json` to remove or modify it. If you want to run other hooks alongside devteam's, add additional entries to the `SessionStart` array — they run in order.

### Notification behavior

Notifications are ON by default in autonomous mode when LEAD halts on a blocked question. Disable per-run with `--no-notify` or persistently: `/lead-mode autonomous --no-notify`.

---

## Requirements

| Dependency | Required | Notes |
|---|---|---|
| superpowers | YES, >= 5.0.0 | THINKER + PLANNER wrap superpowers skills |
| gstack | Recommended | REVIEW (`/codex`), PLAN critiques (`/plan-*-review`), SHIP (`/ship`, `/canary`) degrade gracefully without it |
| macOS / Linux / WSL | YES | Windows-native not supported |

LEAD checks dependencies at startup via `~/.claude/plugins/installed_plugins.json` and warns on degraded modes.

```json
// .claude-plugin/plugin.json — forward-compat declaration
{
  "requires": {
    "plugins": [
      { "name": "superpowers", "marketplace": "claude-plugins-official", "min_version": "5.0.0" },
      { "name": "gstack", "marketplace": "any", "optional": true }
    ]
  }
}
```

### Settings permissions

Add to your project's `.claude/settings.json` (or user settings) to avoid repeated permission prompts:

```json
{
  "permissions": {
    "allow": [
      "Bash(bash *plugins/devteam/bin/slack-append.sh:*)",
      "Bash(bash *plugins/devteam/hooks/session-start.sh)",
      "Read(./.devteam/**)",
      "Write(./.devteam/**)",
      "Edit(./.devteam/**)"
    ]
  }
}
```

---

## Migration from toolbox 0.1.0

devteam is a clean rename — parallel install, not upgrade. Uninstall `toolbox` first.

```bash
# 1. Uninstall old plugin
/plugin uninstall toolbox
/plugin marketplace remove toolbox   # if you added it

# 2. Install devteam
/plugin marketplace add brianyu18/devteam
/plugin install devteam@devteam

# 3. One-time setup
/lead-setup

# 4. Your old /toolbox-feature etc. still work as deprecated aliases
#    (routes to /lead --tier feature)
```

### Command equivalence

| toolbox 0.1.0 | devteam 1.0.0 |
|---|---|
| `/toolbox "task"` | `/lead "task"` |
| `/toolbox-simple "task"` | `/lead --tier simple "task"` |
| `/toolbox-bug "task"` | `/lead --tier bug "task"` |
| `/toolbox-feature "task"` | `/lead --tier feature "task"` |
| `/toolbox-complex "task"` | `/lead --tier complex "task"` |

The old command names continue to work in devteam as deprecated aliases — no changes needed in existing workflows. They will be removed in 2.0.0.

---

## Roadmap

Items tracked in [TODOS.md](TODOS.md). Thresholds that trigger them are in [WATCHLIST.md](WATCHLIST.md).

### Tier 1 — likely within 2–4 weeks of usage

- **Distribution CI/CD** for devteam itself — currently manual `git tag` + GitHub release.
  Trigger: 3+ manual releases in a month, or a release ships with a missed step.

- **Prompt regression eval suite** — lock in current prompt behavior before iterating.
  Trigger: WATCHLIST signal `3a-malformed-output` (3 in 14 days) or `3a-tier-flag-override` (5 in 14 days).

- **Usage telemetry** — local-only JSONL at `~/.claude/devteam/telemetry/<date>.jsonl`.
  Trigger: WATCHLIST signal `3b-manual-log` (2 in 14 days).

### Tier 2 — useful, not urgent

- **Multi-project per repo** — currently one active project per `.devteam/state/`.
- **Cross-session subagent memory** — currently artifact-backed handover only.
- Multi-project context insights (surfaces patterns across projects).

---

## Contributing

### Adding a skill vs. adding an agent

Use the **skill-vs-agent rule**: if the role's core work involves dialogue with the user (asking questions, presenting options, reporting back), it belongs in `skills/` as a SKILL.md. If its core work is heads-down implementation or can be parallelized, it belongs in `agents/` as an agent file.

### Adding a review lens

Drop a `.md` file in `agents/review-lenses/`. Add a regex pattern to `bin/devteam-pick-lenses.sh` so it gets selected for the right file types. Follow the JSON output contract in the existing lens files — review-specialist parses that output.

### Adding a convention stack

See the conventions library section above. Drop a file in `conventions-seed/<category>/`, add a detection entry to `conventions-seed/index.json`. Stack convention files are not role-specific — BUILDER, TESTER, and review-specialist all load applicable ones.

### Design rationale

See [ARCHITECTURE.md](ARCHITECTURE.md) for WHY the architecture is structured the way it is — covering the no-lead-agents decision, the skill-vs-agent rule, the slack contract, the watchlist mechanism, and other non-obvious choices.

---

## License

MIT. See repository root for full license text.
