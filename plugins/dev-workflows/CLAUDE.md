# dev-workflows

Shared development-workflow skills for the lab. Pure skills + two subagents — no MCP server, no dependencies.

## Skills

| Skill | What it does |
|---|---|
| `/brainstorm` | Clarifying questions → 2-3 candidate approaches → evaluation. For open-ended design problems. |
| `/plan-review-simplify` | Explore → Plan → self-review (simplification + correctness) → Present → Execute. For multi-file changes and refactors. |
| `/debug-and-simplify` | Known-issue scan → layered diagnosis (env / services / IPC / app / output) → minimal fix → simplify-review → verify. |
| `/development-log` | Maintains a dated `CHANGELOG` + an `OPEN_ISSUES` (`ISS-###`) tracker with strict templates. |
| `/simplify` | Forks the `simplifier` subagent (read-only) to review the current plan or diff for over-engineering. |
| `/specialist` | Forks the `specialist` subagent: research-first, fetches current docs + real examples, recommends the simplest approach. |

## Subagents

`/simplify` forks **simplifier** and `/specialist` forks **specialist**. Both ship in this plugin's `agents/` directory, so they are available automatically when the plugin is installed — nothing else to set up.

Both subagents are pinned to `model: opus`. With no Opus access, edit each agent's frontmatter (`model: opus` → `model: sonnet`); the skills still work with weaker review/research.

## Notes

- Skills here are generic — no project-specific assumptions. Tailor `/development-log` paths and add a project `CLAUDE.md` / `KNOWN_ISSUES.md` to sharpen `/plan-review-simplify` and `/debug-and-simplify`.
- The `specialist` agent is domain-agnostic by design. To make a sharper domain expert, copy `agents/specialist.md`, rename it, and add authoritative sources + canonical examples (see `examples/plugin-specialist.md` at the repo root for a worked example).
