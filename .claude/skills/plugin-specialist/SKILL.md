---
name: plugin-specialist
description: Research-driven Claude Code plugin / MCP-server specialist for this marketplace. Fetches current docs, studies real plugins from official and community marketplaces, and recommends the simplest architecture that fits the repo's conventions. Use when adding or refining a plugin, choosing an architecture tier, or researching plugin/marketplace patterns.
context: fork
agent: plugin-specialist
argument-hint: [question or topic]
---

Consult the plugin specialist about Claude Code plugin / MCP-server development for this marketplace.

$ARGUMENTS

The specialist researches current documentation and studies real plugins before answering, then recommends the simplest architecture tier that fits this repo's conventions (`.claude/rules/`). Its job is research + architecture, not code review — for over-engineering and complexity checks, use `/simplify`.

This marketplace currently ships only pure-skill plugins (`plugins/dev-workflows/`, `plugins/cluster-ops/`); the specialist points at whichever is the closest structural match. For an MCP-server (Tier 1) plugin there is no local reference yet, so it fetches a current external one and follows `.claude/rules/plugin-development.md`.
