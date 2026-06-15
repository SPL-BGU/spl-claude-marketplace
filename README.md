# SPL Claude Marketplace

A [Claude Code](https://claude.com/claude-code) **plugin marketplace** for the SPL lab @ BGU. Add it once and every lab member gets the same set of skills — shared development workflows and SLURM cluster operations — available across all their projects.

> **Why a marketplace?** Instead of each person copying skill files into their own `~/.claude/`, the marketplace lets everyone install (and update) the lab's skills with one command, and contribute improvements back through normal pull requests.

---

## Install (for lab members)

In any Claude Code session:

```text
# 1. Add the marketplace (once per machine)
/plugin marketplace add SPL-BGU/spl-claude-marketplace

# 2. Install the plugins you want
/plugin install dev-workflows@spl-claude-marketplace
/plugin install cluster-ops@spl-claude-marketplace
```

Or browse interactively with `/plugin`, pick **spl-claude-marketplace**, and install from the menu.

To update later: `/plugin marketplace update spl-claude-marketplace`.

> Replace `SPL-BGU/spl-claude-marketplace` with the actual org/repo path if it differs on your GitHub. For a private repo, make sure your `gh` / git auth can reach it.

---

## What's inside

### `dev-workflows` — shared workflow skills

Pure skills + two subagents. No dependencies, nothing to set up.

| Skill | What it does | When to use |
|---|---|---|
| `/brainstorm` | Clarifying questions → 2-3 candidate approaches → evaluation. | Open-ended design problems. |
| `/plan-review-simplify` | Explore → Plan → self-review → Present → Execute. | Multi-file changes, refactors. |
| `/debug-and-simplify` | Known-issue scan → layered diagnosis → minimal fix → verify. | Pipeline breakage, weird output, "it worked yesterday." |
| `/development-log` | Dated `CHANGELOG` + `OPEN_ISSUES` (`ISS-###`) tracker with strict templates. | After non-trivial changes; to surface what's undocumented. |
| `/simplify` | Forks the `simplifier` subagent to review the current diff/plan for over-engineering. | Before committing a non-trivial diff. |
| `/specialist` | Forks the `specialist` subagent: research-first, fetches current docs + examples. | "Which approach / what does the ecosystem do" questions. |

**Typical loop:** `/brainstorm` or `/specialist` (if approach unclear) → `/plan-review-simplify` → implement → `/simplify` → `/development-log <what>`.

### `cluster-ops` — BGU SLURM cluster operations

One skill (`/cluster-ops`) + six helper scripts to run the BGU cluster (`slurm.bgu.ac.il`) from a local repo: queue status with pending-reason analysis, submit/cancel, sync results, post-mortem (right-size `--mem` from `sacct`/MaxRSS), and prioritize pending array tasks.

> **Requires one-time setup** — passwordless SSH to the cluster and a small `cluster-ops.env`. After installing, see `plugins/cluster-ops/skills/cluster-ops/SETUP.md`. The BGU cluster user guide ships under that skill's `references/`.

Skip this plugin if you don't use the cluster.

---

## Contributing

This is the lab's repo — improvements are welcome via pull request.

- **Edit a skill** → change the relevant `plugins/<name>/skills/<skill>/SKILL.md`, then bump that plugin's `version` in both its `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`.
- **Add a plugin** → follow the checklist in [`CLAUDE.md`](CLAUDE.md#adding-a-plugin-checklist). Each plugin must be self-contained under `plugins/<name>/`. Run `/plugin-specialist <what you want to build>` first — a dev-only command that researches current plugin/MCP docs and comparable plugins, then recommends the simplest architecture.
- **Conventions** are encoded as rules under `.claude/rules/` (`simplification`, `plugin-marketplace`, `plugin-development`) and load automatically when you open this repo in Claude Code.

Open a PR against `main`; describe what changed and which plugin versions you bumped.

---

## Repository layout

```
spl-claude-marketplace/
├── .claude-plugin/
│   └── marketplace.json          ← catalog (what lab members install)
├── plugins/
│   ├── dev-workflows/
│   │   ├── .claude-plugin/plugin.json
│   │   ├── CLAUDE.md
│   │   ├── skills/               ← brainstorm, plan-review-simplify, …
│   │   └── agents/               ← simplifier, specialist
│   └── cluster-ops/
│       ├── .claude-plugin/plugin.json
│       ├── CLAUDE.md
│       └── skills/cluster-ops/   ← SKILL.md, SETUP.md, scripts/, references/
├── .claude/                      ← dev-only tooling (not installed by users)
│   ├── rules/                    ← conventions, auto-loaded in this repo
│   ├── agents/plugin-specialist.md
│   └── skills/plugin-specialist/ ← /plugin-specialist dev command
├── CLAUDE.md
└── LICENSE
```

---

## License

MIT © SPL-BGU. See [LICENSE](LICENSE).
