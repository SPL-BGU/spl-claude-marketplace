# SPL Claude Marketplace

This repository is a Claude Code **plugin marketplace** for the SPL lab @ BGU. Each plugin lives in its own subdirectory under `plugins/` and is installed by lab members via Claude Code's `/plugin` command.

## Structure

- `.claude-plugin/marketplace.json` — marketplace catalog listing every plugin (name, version, source).
- `plugins/<name>/` — each plugin, fully self-contained, with its own `.claude-plugin/plugin.json`, `CLAUDE.md`, and `skills/` (and `agents/` where relevant).
- `.claude/` — **development-only** tooling for contributors, never installed by end users:
  - `.claude/rules/` — the conventions Claude auto-loads while you work in this repo (see below).
  - `.claude/skills/` + `.claude/agents/` — dev commands. Today: `/plugin-specialist`, which forks the `plugin-specialist` agent (research-first plugin/MCP-server architecture advice).
- `install_marketplace.sh` — installs the skills for **Google Antigravity** (Claude Code uses `/plugin` instead). Auto-discovers skills under `plugins/*/skills/*/` and symlinks them, so adding a skills-only plugin needs no change here.

## Available plugins

- **dev-workflows** (`plugins/dev-workflows/`) — shared workflow skills (`/brainstorm`, `/plan-review-simplify`, `/debug-and-simplify`, `/development-log`, `/simplify`, `/specialist`) plus the `simplifier` and `specialist` subagents they fork. Pure skills, no MCP server.
- **cluster-ops** (`plugins/cluster-ops/`) — operate the BGU SLURM cluster from a local repo. One skill (`/cluster-ops`) + six helper scripts. Requires one-time setup (`plugins/cluster-ops/skills/cluster-ops/SETUP.md`).

## Conventions (for contributors)

These three rules under `.claude/rules/` encode the conventions; Claude auto-loads them while you work in this repo:

- `simplification.md` — minimal change, no duplication, proportional complexity, one-consumer rule.
- `plugin-marketplace.md` — plugin isolation, naming, scope boundaries, catalog maintenance.
- `plugin-development.md` — skill conventions, architecture tiers, verification.

### Adding a plugin (checklist)

Before you start, consider `/plugin-specialist <what you want to build>` — it fetches current plugin/MCP docs, studies comparable plugins, and recommends the simplest architecture tier. Then:

1. Plugin is fully self-contained under `plugins/<name>/`, with no cross-plugin imports.
2. Has a `.claude-plugin/plugin.json`, a `CLAUDE.md`, and at least one component (a `skills/` directory and/or an MCP server). Skills-only plugins omit `.mcp.json` and `.claude/settings.json`.
3. Registered in `.claude-plugin/marketplace.json` — the `source` field must match the directory path exactly, and the version must match the plugin's own `plugin.json`.
4. Architecture is the simplest tier that works (pure skill / pure pip preferred).
