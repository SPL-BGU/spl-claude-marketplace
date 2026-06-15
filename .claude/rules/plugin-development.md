---
description: Plugin / MCP-server development guidelines — architecture tiers, MCP servers, skills, and verification. Applies when building a Claude Code plugin.
paths:
  - "plugins/**"
---

## Plugin Development Guidelines

### Architecture tiers — simplest first

Choose the simplest tier that works. When unsure which tier or pattern fits, consult `/plugin-specialist` — it fetches current docs and studies comparable plugins before recommending.

- **Tier 1 — Pure script** (preferred): pip/npm-installable deps only, isolated in a venv / `node_modules`.
- **Tier 2 — System dependencies**: wraps brew/apt/cargo-installable tools; check for the tool and install (or fail with a clear message) before launching.

### MCP server patterns

MCP servers should: use a maintained framework (e.g. FastMCP for Python), accept content-or-path inputs where a tool can take either, keep tools stateless, return structured error objects (`{"error": ...}`) rather than throwing, and apply timeouts to anything that can hang. Start the server natively in your launch script via `exec` so signals and exit codes propagate.

### Tool docstrings are part of the LLM-facing contract

Tool docstrings are read by the LLM that decides which tool to call — vague descriptions cause real tool-selection failures. Patterns that pay off:

- **When-to-use framing** that contrasts the tool with its nearest neighbor (e.g. "use X for …; for … use Y instead").
- **Explicit return shapes** for each non-trivial branch (success / empty / error), with an explicit `status` enum where applicable.
- **Named failure modes** (e.g. "parse error", "missing Java runtime") rather than a generic "error".
- **Cross-references** between near-synonymous tools so the LLM can disambiguate.

References: Anthropic [Define tools](https://platform.claude.com/docs/en/docs/agents-and-tools/tool-use/define-tools) and [Writing tools for agents](https://www.anthropic.com/engineering/writing-tools-for-agents).

### Skill conventions

Every `SKILL.md` must have YAML frontmatter (at least `name`, `description`), lead with any mandatory rules, document the tools it exposes, and include error-handling guidance. Write the `description` so the model can tell when to auto-trigger the skill — name the symptoms / triggers, not just the happy path.

### Verification requirements

1. **Every plugin has a verify script** (e.g. `tests/verify.py`): smoke tests for all MCP tools. It starts the server natively and exercises each tool.
2. **Test every declared tool**: if `.mcp.json` exposes N tools, the verify script must test all N.
3. **Inline test data**: don't depend on external fixture files — define test data in the verify script so it runs anywhere.
4. **Run verification before committing server changes** — this is the equivalent of "tests must pass".
5. **CI gates merges**: wire the verify scripts into CI so PRs to the main branch can't merge red.

### Launch script patterns

Launch scripts create/refresh the venv (`uv` or `python3 -m venv`, or the node equivalent) and `exec` the server directly. Keep the structure identical across a repo's plugins — only the server path and dependency manifest change per plugin.
