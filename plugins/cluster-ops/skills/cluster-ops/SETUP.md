# cluster-ops setup

Six SLURM helper scripts plus one skill prompt, packaged to drop into any project that needs ops over a remote cluster. This file walks through first-time setup; once done, the assistant reads `SKILL.md` and uses the scripts directly.

## 1. Install location

Copy `cluster-ops/` into your project's skill directory. For Claude Code:

```
<your-project>/.claude/skills/cluster-ops/
├── SKILL.md
├── SETUP.md                  ← this file
├── cluster-ops.env           ← create from cluster-ops.env.example
├── scripts/
│   ├── status.sh
│   ├── job.sh
│   ├── sync.sh
│   ├── preflight.sh
│   ├── postmortem.sh
│   └── prioritize.sh
└── references/
    └── cluster_user_guide.md  ← optional: drop in your cluster's user guide, if it has one
```

## 2. SSH key auth

The scripts call `ssh "$REMOTE_USER@$REMOTE_HOST" …` non-interactively. Set up key auth before running anything:

```bash
ssh-copy-id <your-user>@<your-cluster-host>
ssh <your-user>@<your-cluster-host> 'echo ok'   # must succeed without password
```

## 3. Required env vars

Create `cluster-ops.env` next to `SKILL.md` (the scripts source it if present). Or export these in your shell.

| Variable | Required? | What it is | Example |
|---|---|---|---|
| `REMOTE_USER` | **yes** | SSH user on the cluster | `alice` |
| `REMOTE_HOST` | **yes** | SSH host | `slurm.example.edu` |
| `REPO_REMOTE` | **yes** | Repo directory name under `$HOME` on the remote | `my-project` |
| `REMOTE_RESULTS` | no | Absolute remote results dir | default: `~/$REPO_REMOTE/results` |
| `REMOTE_LOG_DIR` | no | Absolute remote logs dir (sbatch `.out` files) | default: `~/$REPO_REMOTE/logs` |
| `REMOTE_RESULTS_GLOBS` | no | Comma-separated globs for `sync.sh` | default: `slurm_*` |
| `LOCAL_RESULTS_DIR` | no | Local results dir for `sync.sh` destinations | default: `<repo>/results` |
| `GPU_PARTITIONS` | no | Comma-separated partition names for `preflight.sh` capacity check | default: empty (skip) |
| `JOB_NAME_PREFIX` | no | Default `--name-prefix` for `postmortem.sh` | default: empty (all jobs) |
| `NICE_VALUE` | no | Deprioritize-Nice for `prioritize.sh` | default: `500` |
| `HAS_SRES` | no | Set to `1` if your cluster has an `sres`-style utilization tool | default: `0` |
| `STATE_FILE` | no | Local cache for `status.sh` Δ diff | default: `~/.cache/cluster-ops-status.json` |

## 4. Manifest contract (for `prioritize.sh`)

`prioritize.sh` is manifest-driven. Your submit script writes one TSV file per submitted array job, naming it `<jobid>.cells.tsv` under `$REMOTE_LOG_DIR`. Format:

```
<task-idx>\t<keep-key>\t<extra-label-1>\t<extra-label-2>\t...
```

- `task-idx` matches the `_<idx>` suffix in SLURM array task IDs (`17389411_3` → idx=3).
- `keep-key` is what `prioritize.sh <jobid> <keep-key>` matches on. Use whatever dimension of your sweep you most often want to prioritize by (model name, dataset, condition).
- Additional columns are optional and free-form (for human inspection).

Example, for a model × condition sweep:

```
0	model-a	on	tools_per-task
1	model-a	off	no-tools
2	model-b	on	tools_per-task
3	model-b	off	no-tools
```

`prioritize.sh 17389411 model-a` keeps tasks 0–1 at Nice=0 and pushes 2–3 to Nice=500.

If your submit flow doesn't produce a manifest, `prioritize.sh` won't work — fall back to manual `scontrol update JobId=<master>_<idx> Nice=N` per task, or skip prioritization entirely.

## 5. Optional: matrix mode for `status.sh`

By default `status.sh` shows one row per remote results dir. If you run a structured sweep (N models × M conditions = fixed cell grid), you can opt into a matrix view by creating `status.config.json` next to the scripts:

```json
{
  "roster": ["model_a_safe_name", "model_b_safe_name"],
  "display_names": {
    "model_a_safe_name": "Model A 7B",
    "model_b_safe_name": "Model B 13B"
  },
  "cells": [
    {"think": "on",  "cond": "baseline"},
    {"think": "off", "cond": "baseline"},
    {"think": "off", "cond": "treatment"}
  ],
  "denominator": 1000,
  "dir_pattern": "slurm_{model}_{think}_{cond}_{jobid}",
  "time_limit_hours": 72
}
```

`dir_pattern` is what your sbatch writes results into; the placeholders are how `status.sh` extracts `(model, think, cond)` from a directory name. The numbers are: `denominator` = expected trials per cell, `time_limit_hours` = your `--time` value (drives the watch list).

Without this file, `--matrix` errors out and the default view is used. The matrix view exists for structured factorial sweeps; if your work doesn't fit that shape, leave it off.

## 6. Optional: project preflight hooks

`preflight.sh` runs `git pull` and a GPU capacity check by default. To add project-specific steps (refresh a plugin venv, sync a dataset, recompile a CUDA kernel), drop a `preflight.local.sh` next to the scripts. It's sourced *inside the remote SSH session* after the git pull, so write it as remote-side bash. Template:

```bash
# preflight.local.sh — runs on the remote cluster
echo "== refresh plugin venv =="
"$PLUG_DIR/.venv/bin/pip" install --upgrade -r "$PLUG_DIR/requirements.txt"
```

If the file doesn't exist, that step is skipped silently.

## 7. Optional: smoke-test the install

```bash
# All --help paths run locally; no SSH required.
bash scripts/status.sh --help
bash scripts/job.sh --help
bash scripts/sync.sh --help
bash scripts/preflight.sh --help
bash scripts/postmortem.sh --help
bash scripts/prioritize.sh --help

# First SSH call — confirms cluster reachability.
bash scripts/status.sh --md
```

If `status.sh` returns "first run (no prior state)" with an empty progress table, the env is wired up correctly — there's just nothing on the cluster yet to report.

## 8. Optional: your cluster's user guide

These recipes follow standard SLURM HPC conventions, but every cluster has local quirks (partition names, QoS tiers, scratch policy). If your cluster publishes a user guide, drop a copy at `references/cluster_user_guide.md` and skim it to verify each recipe against local policy — especially:

| Skill behavior | What to verify in your cluster's docs |
|---|---|
| `preflight.sh` GPU partition list | GPU partition names and `--gpus` syntax |
| `preflight.sh` `sres` capacity view | Whether a cluster-utilization tool exists, and its name |
| `preflight.sh` / `postmortem.sh` `--mem` discipline | RAM-allocation policy ("request the minimum you need") |
| `postmortem.sh` MaxRSS-driven sizing | `sacct` availability and accounting fields |
| `prioritize.sh` is positive-Nice only | Whether unprivileged users may raise priority (negative Nice) or only lower it |
| Cancel recipes | Any per-user cancel restrictions |
| Manifest + array prioritization | Job-array limits (max simultaneously running tasks) |
| Pending REASON cheat-sheet | The REASON glossary (often in an FAQ) |
| `/scratch` / `--tmp` SSD usage (if your jobs use it) | Local scratch / SSD usage policy |

`references/` ships empty — it's a placeholder for whatever guide your cluster provides.

## 9. Cluster-specific knobs

These defaults assume a typical SLURM setup and should port to most installs:

- **Negative Nice is admin-only** on most SLURM installs (by default). The script assumes this and only deprioritizes. If your cluster grants users negative Nice, you can edit `prioritize.sh` to use negative values for the keep-list, but verify with a `--dry-run` probe first.
- **`squeue -r` expansion** — `status.sh` uses `squeue -r` so each array task is its own row. Required for accurate per-cell pending counts on SLURM 22+.
- **`sacct --parsable2`** — `postmortem.sh` parses pipe-delimited rows. If your cluster has a heavily customized `sacct` output, the parser may need adjustment.
- **`sprio`/`scontrol`** — `job.sh` and `prioritize.sh` rely on these being on the login-node PATH. They are on all standard SLURM installs.

## 10. Things this template does NOT include

- A submit script — your project owns that. The skill exposes pre-/post-submit ops only.
- An aggregator or plotter — sync pulls results onto disk; downstream analysis is your call.
- Project-specific routing (where bugs go, who owns which file) — that's `CLAUDE.md` material, not skill material.
