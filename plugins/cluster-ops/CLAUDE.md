# cluster-ops

Operate the BGU SLURM cluster (`slurm.bgu.ac.il`) from a local repo — read queue state, submit/cancel, sync results, post-mortem completed jobs, and prioritize pending tasks. Six helper scripts plus a skill prompt.

## Skill

`/cluster-ops [status | job | preflight | sync | postmortem | prioritize]` — operations only. It reads cluster state, kicks jobs, and syncs results. It never edits experiment code or sbatch scripts.

## One-time setup (required)

This skill does **not** work out of the box — it needs SSH key auth to the cluster and a few env vars. Before first use:

1. Read `skills/cluster-ops/SETUP.md`.
2. Set up passwordless SSH to the cluster (`ssh-copy-id <user>@slurm.bgu.ac.il`).
3. Copy `skills/cluster-ops/cluster-ops.env.example` → `cluster-ops.env` (next to `SKILL.md`) and fill in `REMOTE_USER` and `REPO_REMOTE`. `REMOTE_HOST` already defaults to the BGU login node.

If a script errors with `REMOTE_USER not set`, setup isn't finished.

## Reference

`skills/cluster-ops/references/cluster_user_guide.md` — the BGU CIS HPC cluster user guide. Skim it to verify each recipe against local policy (partition names, QoS tiers, `--mem` discipline, scratch policy).

## Safety

- Destructive ops (`scancel -u <user>`, `rm` on logs/results) require explicit user consent — confirm before each.
- Never mutate experiment code or sbatch scripts from this skill.
- Run `preflight.sh` before submitting a non-trivial sweep.
