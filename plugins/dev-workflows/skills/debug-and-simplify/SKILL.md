---
name: debug-and-simplify
description: Diagnose and fix issues with code execution, external services, dependency failures, or malformed output. Use whenever the pipeline is broken, a run crashed, output looks wrong, files are malformed, or logs contain errors. Check the project's open-issues log first — the symptom may already be a tracked issue with a documented fix.
disable-model-invocation: true
argument-hint: [description of the issue or error message]
---

## Debugging Workflow with Simplification Review

For the issue described in $ARGUMENTS:

### Phase 0: Known-issue scan
Before layered debugging, grep the project's open-issues file (or issue tracker) for the symptom. If it matches a tracked issue, read that entry and the changelog — the root cause, severity, and intended fix may already be documented. Save the user the cost of re-diagnosis.

### Phase 1: Diagnose
Systematically check each layer, stopping when the root cause is found.

**Layer 0 — Environment basics:**
1. Virtual environment / runtime active? (`source .venv/bin/activate && pip list`, or the project's equivalent)
2. Required dependencies installed? (`pip install -r requirements.txt`, `npm install`, etc.)
3. Can the entry point import its dependencies? (`python3 -c "import <pkg>"`, or `node -e 'require("<pkg>")'`)
4. Are language runtimes / system tools at the right version? Project READMEs usually pin these.

**Layer 1 — External services this code talks to:**
1. Is each service reachable? (curl the health endpoint, ping the host)
2. Are credentials / API keys set in the environment?
3. Does a hand-crafted minimal request work (bypass the application's wrapping)?
4. Check the service's own log file or status page for errors.

**Layer 2 — Inter-process / IPC layer (MCP, RPC, child processes):**
1. Are subprocess / plugin servers configured to start? (Read launch scripts, check exit codes.)
2. Do individual calls succeed when invoked directly outside the application?
3. Are response shapes what the caller expects? (Schema mismatches silently fail validation.)
4. Compare default vs. configured behavior — flags or env vars can switch the response shape without telling you.

**Layer 3 — Application execution:**
1. Does a minimal dry run / single-task invocation work?
2. Are input files / fixtures found at expected paths?
3. Is any preparation step (ground-truth generation, cache population, migration) succeeding before the main path?
4. Check timestamped log files for the first error trace, not the last symptom.

**Layer 4 — Output and downstream consumers:**
1. Are output files structurally valid? (`python3 -m json.tool`, `jq`, schema validation)
2. Do output schemas match what downstream code (notebooks, reports, plotting) expects?
3. Is partial output present (suggests a mid-run failure) vs. empty (suggests a startup failure)?

### Phase 2: Fix
Apply the **minimal change** that resolves the root cause:
- Prefer fixing configuration over adding code
- Prefer fixing existing code over adding new files
- Prefer fixing one thing over fixing everything

### Phase 3: Simplify Review
Before committing the fix, review it:
1. Is this the smallest possible change that fixes the issue?
2. Does it introduce any new dependencies or complexity?
3. Could the root cause recur? If so, should a pre-flight check be added?
4. Does the fix maintain compatibility with existing artifacts / consumers?

### Phase 4: Verify
1. Run a quick reproduction of the original failing path to confirm the fix
2. If the issue was in output / analysis, verify downstream consumers still parse correctly
3. Report: what broke, why, what was fixed, verification result

### Common Issues Reference

A generic starter. Extend this table with project-specific symptoms in a sibling `KNOWN_ISSUES.md` if the project has recurring breakages.

| Symptom | Likely cause | Quick check |
|---------|-------------|-------------|
| `ConnectionRefusedError` to localhost service | Service not running | `curl -sf http://localhost:<port>/health` (or equivalent) |
| `ModuleNotFoundError` / `Cannot find module` | Missing dependency in venv / node_modules | `pip install -r requirements.txt` / `npm install` |
| External API returns error payload | Auth / rate-limit / bad input | Test the API directly with known-good input |
| "Not found" error mentioning a model / dataset / asset | Asset not provisioned locally | Re-fetch / re-pull the missing asset |
| Native dependency fails to load (Java, C++ lib, CUDA) | Wrong system version or missing system package | Check the README's "system requirements" section |
| Empty output file | Preparation step (ground truth, fetch, migration) failed silently | Look at the FIRST error in logs, not the last |
| Background process dies after minutes | OOM, external service crash, or oom-killer | Check service log + system memory (`dmesg | tail`, `journalctl`) |
| Stale subprocess / plugin behavior | Cached venv or compiled artifact missing new code | Delete the cache / venv, restart |
| Response shape mismatch (extra keys, missing keys) | Default vs. configured mode mismatch in the called service | Check whether a `verbose` / `mode` / `format` flag changed defaults |
| Output truncated mid-response | Token / length limit, not data-size limit | Raise the limit; don't chase the data path |
