---
description: Marketplace structure rules — plugin isolation, naming, and scope boundaries. Applies when building a Claude Code plugin marketplace (a repo of installable plugins).
paths:
  - "plugins/**"
  - ".claude-plugin/**"
  - "CLAUDE.md"
  - "README.md"
---

## Marketplace Structure Rules

These rules apply to a **plugin marketplace** — a repository that hosts multiple installable Claude Code plugins under `plugins/<name>/`. If your project is a single plugin (not a marketplace), only the isolation and naming sections apply.

### Plugin isolation (CRITICAL)
1. **Self-contained plugins**: Each plugin under `plugins/<name>/` must be fully self-contained. It must work when installed standalone (e.g. via `claude plugin add`).
2. **No cross-plugin imports**: Plugin A must never reference files from Plugin B. No shared code between plugins.
3. **Independent infrastructure**: Each plugin manages its own dependencies, servers, and build artifacts. No shared MCP servers.
4. **Independent MCP servers**: Each plugin declares its own MCP servers in its own `.mcp.json`.
5. **Independent versioning**: Each plugin has its own version in its marketplace entry. Plugins do not share version numbers.

### Naming conventions
- Plugin directory: `plugins/<kebab-case-name>/`
- MCP server name: descriptive, kebab-case
- Skill names: kebab-case (these become the `/command` users type)

### Scope boundaries
- **Root `.claude/`**: development-only tooling (agents, skills, rules). NEVER installed by end users.
- **Root `.claude-plugin/`**: marketplace catalog — declares which plugins exist.
- **Root `CLAUDE.md`**: marketplace-level instructions describing overall structure.
- **`plugins/<name>/CLAUDE.md`**: plugin-specific enforcement rules, loaded when that plugin is active.
- **`plugins/<name>/skills/`**: user-facing skills. Appear as `/commands` for end users.
- **`plugins/<name>/.claude/settings.json`**: pre-approved permissions for that plugin's tools.

Keep the two skill tiers separate: dev skills (`.claude/skills/`) and user-facing skills (`plugins/<name>/skills/`) must NEVER be mixed.

### Adding a new plugin — checklist
1. Plugin is fully self-contained under `plugins/<name>/`.
2. Has a `CLAUDE.md` and at least one component (a `skills/` directory, an MCP server, or both). `.mcp.json` (referencing `${CLAUDE_PLUGIN_ROOT}`) and `.claude/settings.json` are required only when the plugin exposes MCP tools; skills-only plugins omit both.
3. Registered in the marketplace catalog (`.claude-plugin/marketplace.json`, plus any mirror catalog you maintain, e.g. `.cursor-plugin/marketplace.json`).
4. Architecture tier is the simplest possible (pure pip/npm preferred — see `plugin-development.md`).

### marketplace.json maintenance
- Every plugin must have an entry in every catalog you publish.
- The `source` field must match the plugin directory path exactly.
- Version bumps in the catalog must correspond to actual plugin changes.
