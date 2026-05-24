# devteam

Multi-agent dev team in a box for [Claude Code](https://claude.com/claude-code). One **LEAD** skill orchestrates a roster of specialist subagents across 7 sprint phases (THINK / PLAN / BUILD / REVIEW / TEST / SHIP / REFLECT) with parallel fan-out, structured artifact handoffs, and an append-only team-slack audit log per project.

You talk to LEAD. LEAD classifies the task, picks the right phase subset, dispatches workers in parallel, and reports back.

This repo is a **Claude Code plugin marketplace** containing one plugin (`devteam`). Full plugin documentation lives in [`plugins/devteam/README.md`](plugins/devteam/README.md).

## Install

Inside a Claude Code session:

```
/plugin marketplace add brianyu18/devteam
/plugin install devteam@devteam
/lead-setup
```

`/lead-setup` is one-time — it registers the SessionStart hook and seeds the conventions library.

## Quick taste

```
/lead "add dark mode toggle to the settings page"
```

LEAD classifies it (likely `feature`), runs THINK → PLAN → BUILD → REVIEW → TEST → SHIP, checks in at each boundary, and produces a final report. State and the audit log land in `.devteam/state/` in your project.

For specialist commands (`/think`, `/plan`, `/build`, `/review-project`, `/test`, `/ship-project`, `/reflect`), mode reference, conventions library, and architecture rationale — see [`plugins/devteam/README.md`](plugins/devteam/README.md).

## Updating

```
/plugin marketplace update devteam
/plugin update devteam@devteam
```

## Uninstalling

```
/plugin uninstall devteam@devteam
/plugin marketplace remove devteam
```

## Requirements

- [superpowers](https://github.com/obra/superpowers) >= 5.0.0 (required — THINKER and PLANNER wrap superpowers skills)
- [gstack](https://github.com/gstack) (recommended — REVIEW, PLAN critiques, and SHIP chains degrade gracefully without it)
- macOS / Linux / WSL

## Repo structure

```
devteam/                                  # marketplace root
├── .claude-plugin/
│   └── marketplace.json                 # marketplace manifest
├── plugins/
│   └── devteam/                          # the plugin
│       ├── .claude-plugin/plugin.json
│       ├── README.md                    # full plugin documentation
│       ├── ARCHITECTURE.md              # design rationale
│       ├── CHANGELOG.md
│       ├── skills/                      # LEAD, THINKER, PLANNER, SHIPPER, REFLECTOR
│       ├── agents/                      # BUILDER, review-specialist, TESTER, + 4 utility
│       ├── commands/                    # /lead, /think, /plan, /build, etc.
│       ├── bin/                         # slack-append, stack-detect, lens-pick, watchlist
│       ├── conventions-seed/            # per-stack coding conventions (8 stacks)
│       ├── hooks/                       # SessionStart hook
│       └── docs/
└── README.md
```

## History

devteam is a clean rename of the earlier `toolbox` plugin (v0.1.0). The 1.0.0 rebuild replaced the workflow-router design with a multi-agent team architecture — see the plugin's [CHANGELOG.md](plugins/devteam/CHANGELOG.md) and [ARCHITECTURE.md](plugins/devteam/ARCHITECTURE.md) for the redesign rationale. Old `/toolbox*` commands are preserved as deprecated aliases (removal in 2.0.0); see the plugin README's migration section.

## License

MIT. See [LICENSE](LICENSE) if present in the repo, or the plugin's `plugin.json`.
