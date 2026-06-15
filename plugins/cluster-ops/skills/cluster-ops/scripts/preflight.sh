#!/usr/bin/env bash
# Pre-submit cluster refresh + capacity snapshot.
#
# Pulls the remote repo, surfaces GPU pool capacity for the partitions you
# care about, and (optionally) sources preflight.local.sh for project hooks.
#
# Usage:
#   bash preflight.sh
#
# Env (load via cluster-ops.env if present):
#   REMOTE_USER, REMOTE_HOST, REPO_REMOTE   (required)
#   GPU_PARTITIONS                          (comma-separated; default empty)
#   HAS_SRES                                (1 to call an sres-style utilization tool)
#
# Optional: drop preflight.local.sh next to the scripts to add project-specific
# checks (venv refresh, dataset sync, etc.). It's sourced inside the remote
# SSH session after git pull. Write it as remote-side bash.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for arg in "$@"; do
    case "$arg" in -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
done

[ -f "$SCRIPT_DIR/../cluster-ops.env" ] && . "$SCRIPT_DIR/../cluster-ops.env"

: "${REMOTE_USER:?REMOTE_USER not set — see SETUP.md}"
: "${REMOTE_HOST:?REMOTE_HOST not set — see SETUP.md}"
: "${REPO_REMOTE:?REPO_REMOTE not set — see SETUP.md}"

GPU_PARTITIONS="${GPU_PARTITIONS:-}"
HAS_SRES="${HAS_SRES:-0}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# If a local hook exists, slurp it into a heredoc-safe blob for remote eval.
LOCAL_HOOK=""
if [ -f "$SCRIPT_DIR/../preflight.local.sh" ]; then
    LOCAL_HOOK=$(cat "$SCRIPT_DIR/../preflight.local.sh")
fi

ssh "${REMOTE_USER}@${REMOTE_HOST}" \
    "REPO=$REPO_REMOTE GPU_PARTITIONS='$GPU_PARTITIONS' HAS_SRES=$HAS_SRES \
     LOCAL_HOOK=$(printf '%q' "$LOCAL_HOOK") bash -s" <<'REMOTE'
set -eo pipefail

EXPT="$HOME/$REPO"

echo "== git pull =="
if [ ! -d "$EXPT/.git" ]; then
    echo "    $EXPT is not a git repo — skipping pull" >&2
else
    echo "--- $EXPT"
    git -C "$EXPT" fetch --quiet origin
    before=$(git -C "$EXPT" rev-parse HEAD)
    git -C "$EXPT" pull --ff-only --quiet
    after=$(git -C "$EXPT" rev-parse HEAD)
    if [ "$before" = "$after" ]; then
        echo "    already up to date ($after)"
    else
        echo "    $before → $after"
        git -C "$EXPT" log --oneline "$before..$after"
    fi
fi

if [ -n "$LOCAL_HOOK" ]; then
    echo
    echo "== project hook (preflight.local.sh) =="
    eval "$LOCAL_HOOK"
fi

if [ -n "$GPU_PARTITIONS" ]; then
    echo
    echo "== GPU pool capacity =="
    # idle+mix nodes are the relevant signal for one-GPU-per-job sbatches.
    IFS=',' read -ra PARTS <<< "$GPU_PARTITIONS"
    for part in "${PARTS[@]}"; do
        free=$(sinfo -h -p "$part" -t idle,mix -o '%n' 2>/dev/null | wc -l | tr -d ' ')
        total=$(sinfo -h -p "$part" -o '%n' 2>/dev/null | wc -l | tr -d ' ')
        printf "    %-20s  %s/%s nodes idle-or-mixed\n" "$part" "$free" "$total"
    done
fi

if [ "$HAS_SRES" = "1" ]; then
    echo
    echo "== sres (cluster utilization) =="
    sres_block=$(sres 2>/dev/null | sed -n '/GPU UTILIZATION/,/Available Resources/p' | sed '$d')
    if [ -z "$sres_block" ]; then
        echo "    (sres GPU UTILIZATION section not found — output format may have changed)"
    else
        printf '%s\n' "$sres_block" | sed 's/^/    /'
    fi
fi

echo
echo "Preflight complete."
REMOTE
