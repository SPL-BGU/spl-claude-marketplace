---
description: Global simplification principle applied to all code changes
paths:
  - "**"
---

## Simplification Principle

Before writing or modifying code, verify:

1. **Existing-code check**: Search the codebase for existing scripts, patterns, or utilities before adding new ones. If the repo already solves a similar problem, match that solution. Do not duplicate.
2. **Minimal change**: Implement the smallest change that solves the problem. No "just in case" code.
3. **Proportional complexity**: Solution complexity should match problem complexity. A simple tool does not need a class hierarchy.
4. **One-consumer rule**: Do not create abstractions (base classes, utility modules, shared libraries, plugin architectures) with only one consumer. Inline until 2+ consumers actually need it.
5. **File-count check**: If your change creates new files at the repository root, reconsider. New files should live inside the relevant module/component directory, or in `.claude/` for dev tooling.
6. **Script reuse**: Before writing a new shell script, check whether an existing one already handles the case. Adapt rather than create.
7. **Simplest architecture tier**: Default to the simplest tier that works (pure pip/npm deps in an isolated venv before system dependencies; configuration before code). Use an existing known-good component in the repo as the reference.
