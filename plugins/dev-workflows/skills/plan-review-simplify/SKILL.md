---
name: plan-review-simplify
description: Create an execution plan with built-in review for correctness and simplification. Use for multi-file changes, refactoring, or any change spanning multiple files where the cost of getting it wrong is non-trivial. Trigger whenever the user asks to plan, design, or think through an implementation before coding — especially if the change could alter contracts, schemas, or behavior other code depends on.
disable-model-invocation: true
argument-hint: [task description]
---

## Planning Workflow with Review and Simplification

For the task described in $ARGUMENTS:

### Phase 1: Explore
Read relevant existing code using Grep and Glob. Identify reusable patterns and existing state so the plan doesn't reinvent them.

A reasonable reference surface (adapt to the project at hand):
- Entry-point / main module(s) — where execution starts
- Public API or contract surface — what other code depends on
- Project docs / README / CLAUDE.md — methodology, conventions, constraints
- Changelog or development log — recent changes; check first to avoid re-solving something already landed
- Open-issue tracker (file or external) — many "should we fix X?" questions already have a written answer

Checking the changelog and open issues up front prevents duplicate work and surfaces whether the ask is already tracked.

### Phase 2: Plan
Design the implementation approach covering:
- **Objective**: One sentence describing the goal
- **Analysis**: Current state, what needs to change, existing code to reuse
- **Scope**: Which files are affected? Does this change any public contract or behavior other code depends on?
- **Reproducibility / backwards compatibility**: Will existing artifacts (results, configs, saved state, downstream consumers) remain valid? Are migrations or new baselines needed?
- **Files to modify**: Table of `file | action (create/modify/delete) | description`
- **Execution steps**: Numbered checklist
- **Validation strategy**: How to verify the change works (test run, result comparison, smoke check)
- **Documentation**: Which entry belongs in the project's changelog; does it resolve any tracked issue?

### Phase 3: Review
Before presenting the plan, review it for simplification and correctness:

**Simplification:**
- Can any proposed new file be merged into an existing file?
- Can any proposed new script reuse existing logic?
- Would a senior engineer say "this is more code than necessary"?
- Does the change avoid adding abstractions with only one consumer?

**Integrity:**
- Does the change preserve compatibility with existing artifacts (results, saved state, downstream consumers)?
- Are evaluation metrics, success criteria, or measured invariants unchanged (or intentionally updated)?
- Does the change respect the public contract of any module/API it touches?
- Is the change documented if it affects methodology or behavior, and queued for the changelog?
- Does it close or partially address any tracked issue?

**Correctness:**
- Are paths, identifiers, and external service names resolved correctly?
- Does error handling cover failure modes that can actually occur (external service errors, timeouts, malformed input)?

If concerns found: revise the plan. Note what changed and why.

### Phase 4: Present for Approval
Present plan to user, noting:
- Open decisions requiring user input
- Any impact on existing artifacts or reproducibility

Do NOT proceed until approved.

### Phase 5: Execute
Execute steps in order. After completion:
1. Run a quick smoke test (smallest realistic invocation that exercises the change)
2. Verify output format matches expected structure
3. Append an entry to the project's changelog (date, motivation, files touched, compatibility notes). If the change closes or narrows a tracked issue, move or update that entry.
4. Summarize changes, key decisions, validation results

## Fast Mode
If user says "fast mode", "just do it", or "skip planning" — execute immediately without the planning workflow.

## Simple Tasks (No Planning Required)
Skip planning for:
- Single-file edits under ~50 lines
- Answering questions or explaining code
- Running existing scripts without modification
- Git operations
- Documentation-only changes
