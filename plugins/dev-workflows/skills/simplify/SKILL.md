---
name: simplify
description: Review current plan or code changes for unnecessary complexity, contract drift, and backwards-compatibility issues. Flags over-engineering and changes that could invalidate existing artifacts or consumers.
context: fork
agent: simplifier
argument-hint: [description of what to review]
---

Review the current work for unnecessary complexity and correctness.

$ARGUMENTS

If no specific target is given, review the most recent changes (check git diff or the current plan).

Reference files worth pulling into context (adapt to the project):
- Entry-point / main module(s) — where execution starts
- Public API or contract surface — what other code depends on
- Project docs / README / CLAUDE.md — methodology, conventions, constraints
- Changelog — recent landed changes; cross-check that the proposed change doesn't duplicate something already there
- Open-issues file — tracked gaps; flag if the review's target invalidates an open-issue fix sketch
