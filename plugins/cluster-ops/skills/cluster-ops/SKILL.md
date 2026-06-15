---
name: cluster-ops
description: Operate a SLURM cluster from a local repo — queue + pending-reason, submit/cancel, sync results, post-mortem completed jobs (right-size --mem from sacct/MaxRSS), prioritize pending tasks via per-task Nice. Read-only over experiment state.
argument-hint: [status | job | preflight | sync | postmortem | prioritize]
---

> User asked for: $ARGUMENTS — pick the matching recipe below.

## Setup first

This skill assumes `SETUP.md` has been completed: required env vars set (`REMOTE_USER`, `REMOTE_HOST`, `REPO_REMOTE`), SSH key auth working to the cluster, and optional features (matrix mode, `sres`, plugin hooks) configured if you want them. If any script errors with "REMOTE_USER not set", go finish setup.

## Why this skill exists

Triggers (so the skill auto-matches): "cluster status", "what's running", "why is it pending", "when will it run", "queue position", "queue rank", "ETA for job", "submit", "cancel jobs", "sync results", "postmortem", "memory headroom", "prioritize", "deprioritize", "nice value", "let job X finish first".

Every session you re-derive the same SSH queue queries, `.out`-file grep patterns, rsync invocations, and sacct memory-headroom recipes. The cluster state is persistent but the assistant's working set isn't. This skill pins the conventions in one place and exposes six short helper scripts. Read it before running SSH/rsync commands ad-hoc.

The skill is **operations only** — read state, kick jobs, sync results. It never edits experiment code or sbatch scripts; those have their own routing.

## Safety

- **Destructive ops require explicit user consent**: `scancel -u <user>` (kills all jobs), `rm` on logs or results. Confirm before each.
- **Never mutate experiment code or sbatch scripts from this skill.** Those live in the project repo with their own conventions.
- **Preflight before submit** when applicable (`scripts/preflight.sh`) — pulls the remote repo, surfaces GPU pool capacity in one shot. Submitting against a saturated pool or with stale code wastes time.

## Operations scripts (under `scripts/`)

Six scripts: `status.sh`, `job.sh`, `sync.sh`, `preflight.sh`, `postmortem.sh`, `prioritize.sh`. All take env-var overrides (see `SETUP.md`); core defaults from `cluster-ops.env` if present.

### `scripts/status.sh` — cluster status snapshot

One SSH call (`squeue` + per-results-dir `wc -l trials.jsonl`). Local Python diffs against `~/.cache/cluster-ops-status.json` (overridable via `STATE_FILE` env) and renders sections, in this order:

1. **Header** — `## Status — ~Xh since last check` (or `first run` when the cache file is absent).
2. **What changed** — bullets for results dirs that flipped to ✓ this window and dirs that newly started accumulating trials. Omitted if nothing changed.
3. **Progress table** — one row per results dir, columns: dir | trials | Δ | pace | ETA. (Replaced by the matrix view if `--matrix` + config is supplied; see below.)
4. **Roll-up** — Running N jobs (IDs) · Pending grouped by REASON.

The cache file is local-only and pure scratch — `rm ~/.cache/cluster-ops-status.json` to reset (next run will be a "first run" with no Δ).

**Output mode** auto-selects from stdout TTY-detect: ANSI-coloured aligned text in a real terminal, GitHub-flavoured markdown when piped or run via tooling. Override with flags:

```bash
bash scripts/status.sh                 # auto (terminal in zsh, md in pipes)
bash scripts/status.sh --md            # force markdown
bash scripts/status.sh --terminal      # force pretty
bash scripts/status.sh --no-color      # strip ANSI from terminal mode
bash scripts/status.sh --matrix        # opt-in N-model × M-cell matrix (needs status.config.json)
```

Matrix mode is optional and only useful if you run a structured sweep with a fixed roster × condition grid. Configure via `status.config.json` next to the script — see `SETUP.md` for the schema. Without the file, `--matrix` errors out.

### `scripts/job.sh` — single-job inspection

Use when `status.sh`'s aggregate view doesn't fit — one-off probes, smoke sbatches, or drilling into one specific job. One SSH call: `squeue -j <id>` + `sacct -j <id>` + (when STATE=PENDING) queue assessment + log tail. Markdown output, pastes cleanly into chat.

```bash
bash scripts/job.sh <jobid>                 # squeue + sacct + queue assessment + last 25 log lines
bash scripts/job.sh <jobid> --lines 100     # custom tail size
bash scripts/job.sh <jobid> --no-log        # squeue/sacct + queue assessment only (skip log)
```

Handles three states gracefully: pending (squeue + queue assessment), running (live tail), completed/cancelled (sacct shows terminal state). Log tail uses the glob `${REMOTE_LOG_DIR}/*-<jobid>.out` — adjust `REMOTE_LOG_DIR` in `cluster-ops.env` if your sbatch writes logs elsewhere. Numeric-jobid guard catches the easy mistake of typing a script name.

**Queue assessment** (auto-renders when STATE=PENDING) answers "when does this move from PD to RUNNING?":

- **Priority** — `sprio` total priority value. Compare with peers to see whether you're scheduled to win contention.
- **Same-class queue rank** — `#N of M` pending jobs requesting the same GPU class as yours (derived from your job's `tres-per-job`). Filter is anchored on the colon (`gpu:rtx_6000:` ≠ `gpu:rtx_pro_6000:`) so similarly-named classes don't cross-contaminate.
- **REASON breakdown for jobs ahead** — `Priority=2 JobArrayTaskLimit=6 …`. Crucial for interpreting rank: a high #N can still translate to a quick start if most ahead are blocked on `MaxGRESPerAccount`, `JobArrayTaskLimit`, or `Dependency` rather than competing for free GPUs.
- **SLURM earliest-slot estimate** — `<ISO> → best-case ~Xm` or `next backfill window (best-case lower bound, not a guarantee)`. Computed from SLURM's `StartTime` via `date -d`. The estimate is the earliest slot the backfill scheduler can verify *assuming your job is next in line*; higher-priority arrivals can leapfrog, so it's a lower bound that frequently slips.

Caveats: neither rank nor SLURM's earliest-slot estimate is a real ETA. Rank counts jobs ahead by priority; many of them are blocked on QoS / array-throttle / dependencies and won't compete. The estimate is a backfill window, not a commitment. The honest signal is the *combination*: rank tells you who's ahead and why (REASON breakdown), and the estimate tells you when SLURM next plans to even look at your job. Non-GPU jobs skip the same-class filter and just get priority + estimate.

### `scripts/sync.sh` — pull results locally

`rsync -av --update` from one or more remote globs into a local subdir. Never deletes anything.

```bash
bash scripts/sync.sh                          # → <local-results-dir>/cluster-YYYYMMDD/
bash scripts/sync.sh results/my-custom-run    # → explicit dir
```

Remote source globs come from `REMOTE_RESULTS_GLOBS` (comma-separated, defaults to `slurm_*` only). Add more globs in `cluster-ops.env` if you also want probe/smoke output dirs. Reports per-glob dir-count delta so you can tell whether each pattern added anything. To clear cancelled-job `.out` files on the remote side, tell the user explicitly what IDs you intend to delete and wait for confirmation before `ssh … rm`.

### `scripts/preflight.sh` — pre-submit refresh + capacity

Run before submitting any non-trivial sweep. Does, in one SSH call:

1. `git pull --ff-only` on the remote repo (`$REPO_REMOTE` under `$HOME`).
2. **GPU pool capacity** — `sinfo -p <part> -t idle,mix` for each entry in `GPU_PARTITIONS` (comma-list in `cluster-ops.env`). The free-node count tells you whether your submit will queue immediately or sit in `PENDING(Resources)`.
3. **`sres` snapshot** (skipped unless `HAS_SRES=1`) — one-glance cluster utilization view, if your cluster provides an `sres`-style utilization tool.
4. **Optional project hooks** — if `preflight.local.sh` exists in the skill dir, it's sourced inside the SSH session for project-specific checks (venv refresh, dataset sync, etc.). Template stub provided.

```bash
bash scripts/preflight.sh
```

### `scripts/prioritize.sh` — bias which pending tasks run next

Per-array-task `scontrol update Nice=N` driven by a manifest your submit script writes (`<remote-logs-dir>/<jobid>.cells.tsv`, format: `idx<TAB>key<TAB>extra1<TAB>extra2…`). Tasks whose `key` is in the keep-list stay at `Nice=0`; every other pending task gets `Nice=$NICE_VALUE` (default 500) so the kept tasks grab the next free slot.

**Direction is one-way**: negative Nice (raise priority above default) is admin-only on most SLURM installs — typically `nice=100` is accepted but `nice=-1000` is denied for an unprivileged user. The only lever you have is *deprioritizing the rest*.

```bash
bash scripts/prioritize.sh <jobid> <key1> [<key2> …]   # keep these keys at Nice=0
bash scripts/prioritize.sh <jobid> --reset             # all cells back to Nice=0
bash scripts/prioritize.sh <jobid> --dry-run <key>     # show plan without applying
```

Already-running tasks are skipped (Nice has no effect once dispatched). Idempotent — safe to re-run with a different keep-list. If the manifest is missing, the script exits 2 and tells you so; fall back to manual `scontrol update JobId=<master>_<idx> Nice=N` per task.

The manifest contract: your submit script must write `<jobid>.cells.tsv` to `$REMOTE_LOG_DIR` immediately after `sbatch` returns. First column is task index (matches `_<idx>` in array task IDs), second column is the keep-key prioritize matches on, remaining columns are free-form labels. See `SETUP.md` for an example.

### `scripts/postmortem.sh` — completed-job introspection (`sacct`)

Pulls `sacct` for completed jobs (optionally filtered by name prefix), merges parent + `.batch` step rows so MaxRSS lands in the same row as State/Elapsed/ExitCode, then computes a memory-headroom recommendation across the window. Closes the loop on the "request the minimum RAM you need" guidance most HPC clusters publish.

Use after a sweep finishes to: spot OOMs (`Comment` = `OOM-Kill`), find jobs that approached `--time`, and right-size `--mem` for the next sweep without manual `sacct` per job.

```bash
bash scripts/postmortem.sh                                  # last 7 days, all your jobs
bash scripts/postmortem.sh --since 2026-04-22               # specific window
bash scripts/postmortem.sh --jobs 17130166,17130167         # specific job ids
bash scripts/postmortem.sh --name-prefix pddl_              # filter by job-name prefix
```

If you set `JOB_NAME_PREFIX` in `cluster-ops.env`, it's used as the default for `--name-prefix`.

## Recipes

### "What's the cluster status?"

1. `bash scripts/status.sh` — queue + per-results-dir progress.
2. If any job has been stuck at the same progress for >30 min → tail the `.out` file to see the last line:
   ```bash
   ssh "$REMOTE_USER@$REMOTE_HOST" 'tail -50 '"$REMOTE_LOG_DIR"'/*-<jobid>.out'
   ```

### "Sync results and inspect"

1. `bash scripts/sync.sh` — rsync into `<local-results>/cluster-<today>/`.
2. `bash scripts/postmortem.sh` — sacct table + memory-headroom recommendation. Surface any OOM rows or jobs that approached `--time` to the user.
3. Hand off to your own aggregation/plotting (this skill stops at "results on disk").

### "Submit and watch"

1. `bash scripts/preflight.sh` — pulls the remote repo, refreshes any project hooks, surfaces GPU pool capacity. Halts on failure.
2. Submit your sbatch (this skill does not own the submit script — call your project's submit path from your own commands).
3. `bash scripts/job.sh <jobid>` — pending state shows queue position + estimated start; running state shows live log tail.
4. When complete, `bash scripts/sync.sh` to pull results.

### "Prioritize a task during a contended sweep"

1. `bash scripts/status.sh` — identify which pending task you want to win the next free slot. Note its keep-key (model name, condition, whatever your manifest uses).
2. `bash scripts/prioritize.sh <jobid> --dry-run <keep-key>` — inspect the plan.
3. `bash scripts/prioritize.sh <jobid> <keep-key>` — apply.
4. To reset later: `bash scripts/prioritize.sh <jobid> --reset`.

Caveats:
- Nice ordering only matters while tasks are PENDING. RUNNING tasks are past the scheduling decision; the script skips them and reports the count.
- If pending tasks are stuck on a node-specific reservation (REASON=`ReqNodeNotAvail`/`Reservation`), Nice ordering changes who-goes-first but doesn't dislodge the reservation. Check `status.sh`'s queue table and the Pending REASON cheat-sheet below.

### "Cancel jobs"

Specific IDs first; pipe `squeue → awk → scancel` when you want a name-prefixed batch gone:

```bash
ssh "$REMOTE_USER@$REMOTE_HOST" 'scancel <id> <id> …'                                              # specific jobs
ssh "$REMOTE_USER@$REMOTE_HOST" "squeue --me -h -o '%i %j' | awk '\$2 ~ /^<prefix>/ {print \$1}' \
                                  | xargs --no-run-if-empty scancel"                                # by name prefix
```

**Do NOT use `scancel --name=<prefix>*`** — verified on SLURM 25.11.4: `--name` is exact-string match (comma-separated list of literal names), not a glob/regex, so `<prefix>*` silently matches zero jobs and the cancel is a no-op with no error. Use the squeue→awk→xargs pipe above to filter by name prefix.

`scancel -u <user>` (nuke all, no name filter) needs an explicit user request — it will terminate jobs that have been running for hours and may not be related to the work in scope. Confirm first.

### Pending REASON cheat sheet

When `status.sh`'s Pending table shows a non-trivial REASON, here's what to do (your cluster's FAQ usually has the canonical descriptions):

| REASON | What it means | Action |
|---|---|---|
| `Resources` | The requested partition pool is full. | Wait, or switch to a less-saturated GPU class if your workload fits. |
| `Priority` | Preempted by a higher-priority job (e.g. a privileged "golden-ticket" QoS tier). | Wait — usually clears in minutes. |
| `QOSMaxJobsPerUserLimit` | Per-user concurrent-job cap reached. | Wait for one of your other jobs to finish, or scancel a low-priority one. |
| `MaxGRESPerAccount` | Per-account GPU cap (relevant for high-priority QoS). | Wait. Not applicable on plain `main`. |
| `PartitionTimeLimit` | `--time` exceeds partition's max. | Edit `#SBATCH --time` and resubmit. |
| `ReqNodeNotAvail` / `Reservation` | A reservation is blocking the requested node. | Wait for the reservation window, or remove `--nodelist`/`--constraint`. |
| `JobArrayTaskLimit` | Per-job array task-concurrency cap (`%N` in `--array=`). | Tasks will rotate in as earlier ones complete; nothing to do. |
| `Dependency` | Waiting on an `afterok`/`afterany` job. | Check the parent job; this one cannot start until it finishes. |

### "Debug a job that exited with FAIL"

1. `bash scripts/job.sh <jobid>` — sacct shows the terminal state and exit code; log tail shows the last 25 lines.
2. For deeper traces: `ssh "$REMOTE_USER@$REMOTE_HOST" 'cat '"$REMOTE_LOG_DIR"'/*-<jobid>.out'`.
3. If the job OOM-killed, `bash scripts/postmortem.sh --jobs <jobid>` returns MaxRSS — bump `--mem` and resubmit.

## Things this skill does NOT do

- Edit experiment code or sbatch scripts (those have their own conventions in your project repo).
- Submit jobs (call your project's submit path from your own commands; this skill exposes preflight, status, and post-submit ops).
- Aggregate, plot, or analyze results (sync pulls them onto disk; downstream tooling is your call).
- Resolve dependency bugs in your job — it just reports terminal state and tail.
