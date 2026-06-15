---
name: brainstorm
description: Guided brainstorming for features, architecture, or design decisions. Use for open-ended problems where multiple approaches should be explored before committing to implementation.
disable-model-invocation: true
argument-hint: [topic or problem description]
---

## Brainstorm: $ARGUMENTS

### Phase 1: Understand

Before brainstorming, build context:

1. Read project README, CLAUDE.md, and architecture docs if they exist
2. Use Grep/Glob to find code related to the topic
3. Identify existing patterns, constraints, and prior art in the codebase
4. Summarize findings in 3-5 bullet points

If $ARGUMENTS is empty, ask the user what they want to brainstorm before proceeding.

### Phase 2: Explore Approaches

**Clarify first.** Present a numbered list of clarifying questions (max 5) with suggested answers in parentheses. Wait for the user to respond before proposing approaches.

Example format:
> 1. Should this be user-facing or internal? (likely user-facing based on X)
> 2. Performance constraint? (probably not critical given Y)

**Then propose 2-3 approaches.** For each approach:

- **Name**: Short descriptive label
- **How it works**: 2-3 sentences
- **Pros**: Bullet list
- **Cons**: Bullet list
- **Effort**: Low / Medium / High
- **Fits existing patterns?**: Yes/No with brief explanation

Highlight which approach you recommend and why.

### Phase 3: Converge

Before presenting to the user, self-review the recommended approach:

- Is it the simplest solution that solves the problem?
- Does it avoid unnecessary abstractions or new files?
- Are there existing utilities or patterns it should reuse?
- What are the biggest risks?

Present the refined recommendation as a summary block:

```
## Brainstorm Result
**Problem**: [one sentence]
**Chosen approach**: [name]
**Key decisions**: [bullet list of 2-4 decisions]
**Risks**: [bullet list]
**Estimated scope**: [files to touch, rough size]
```

**STOP. Ask the user to approve before proceeding.**

### Phase 4: Handoff to Implementation

After approval, transition to implementation planning:

1. If the project has a planning skill (e.g., `/plan-review-simplify`, `/simplify`), suggest invoking it with the brainstorm result as input
2. Otherwise, produce a simple execution checklist: files to modify, order of changes, validation steps
3. Do NOT start coding — only plan

If the user says "just do it" or "skip planning", proceed directly to implementation.
