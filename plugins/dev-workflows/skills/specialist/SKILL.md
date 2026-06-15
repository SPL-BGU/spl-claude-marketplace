---
name: specialist
description: Consult a research-first specialist that fetches current documentation and studies real-world examples before answering, then recommends the simplest approach that works. Use for "what should we build / which approach / what does the ecosystem do" questions where current, well-sourced research beats memorized knowledge.
context: fork
agent: specialist
argument-hint: [question or topic to research]
---

Consult the research specialist about: $ARGUMENTS

The specialist researches current documentation and real-world examples before answering, then recommends the **simplest approach that works**. Its job is research + recommendation, not code review — for over-engineering and complexity checks, use `/simplify` (the `simplifier` agent).

If your repo already has a known-good reference implementation for the topic at hand, point the specialist at it — it will adapt that pattern rather than invent a new one.

**Make it domain-specific.** This is a general-purpose specialist. To turn it into a sharper expert for a recurring domain (plugin development, database tuning, a specific framework), copy `agents/specialist.md` to a new name and fill in the domain's authoritative sources, canonical examples, and decision rules. `examples/plugin-specialist.md` is a fully worked example — a research-driven Claude Code plugin / MCP-server specialist.
