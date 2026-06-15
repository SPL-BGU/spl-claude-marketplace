#!/usr/bin/env bash
# rsync remote cluster results into a local subdir.
# Never deletes anything remotely.
#
# Usage:
#   bash sync.sh                          # → $LOCAL_RESULTS_DIR/cluster-YYYYMMDD/
#   bash sync.sh results/my-run           # → explicit path (absolute or relative)
#
# Env (load via cluster-ops.env if present):
#   REMOTE_USER, REMOTE_HOST, REPO_REMOTE   (required)
#   REMOTE_RESULTS                          (default ~/$REPO_REMOTE/results)
#   REMOTE_RESULTS_GLOBS                    (comma-separated, default "slurm_*")
#   LOCAL_RESULTS_DIR                       (default <repo>/results)

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for arg in "$@"; do
    case "$arg" in -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
done

[ -f "$SCRIPT_DIR/../cluster-ops.env" ] && . "$SCRIPT_DIR/../cluster-ops.env"

: "${REMOTE_USER:?REMOTE_USER not set — see SETUP.md}"
: "${REMOTE_HOST:?REMOTE_HOST not set — see SETUP.md}"
: "${REPO_REMOTE:?REPO_REMOTE not set — see SETUP.md}"

REMOTE_RESULTS="${REMOTE_RESULTS:-\$HOME/$REPO_REMOTE/results}"
REMOTE_RESULTS_GLOBS="${REMOTE_RESULTS_GLOBS:-slurm_*}"

if [ -n "$LOCAL_RESULTS_DIR" ]; then
    LOCAL_ROOT="$LOCAL_RESULTS_DIR"
else
    # Default: <repo>/results when run from within a project repo, else cwd/results.
    LOCAL_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || pwd)/results"
fi

DEST="${1:-$LOCAL_ROOT/cluster-$(date +%Y%m%d)}"

while [[ $# -gt 1 ]]; do
    case "$2" in
        -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) shift ;;
    esac
done

mkdir -p "$(dirname "$DEST")"
DEST_ABS="$(cd "$(dirname "$DEST")" && pwd)/$(basename "$DEST")"

# Refuse to dump remote dirs flat into the local results root — every sync
# must land in a named subdir so different sweeps stay separable.
if [ "$DEST_ABS" = "$LOCAL_ROOT" ]; then
    echo "ERROR: refusing to sync into bare $LOCAL_ROOT — pass a subdir like cluster-DATE" >&2
    exit 2
fi

mkdir -p "$DEST"

IFS=',' read -ra GLOBS <<< "$REMOTE_RESULTS_GLOBS"

echo "Syncing ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_RESULTS}/{${REMOTE_RESULTS_GLOBS}} → $DEST"

declare -a BEFORE AFTER
for i in "${!GLOBS[@]}"; do
    pat="${GLOBS[$i]}"
    # Count by the leading directory portion of the glob (everything up to the
    # first `*`), so nested patterns like `smoke/probe_*` still report changes.
    name_pat="$(basename "$pat")"
    BEFORE[$i]=$(find "$DEST" -maxdepth 2 -type d -name "$name_pat" 2>/dev/null | wc -l | tr -d ' ')
done

# First glob is "must succeed"; subsequent ones are best-effort (often empty
# on a fresh cluster between probes — `|| true` keeps sync from failing).
for i in "${!GLOBS[@]}"; do
    pat="${GLOBS[$i]}"
    [ "$i" -gt 0 ] && echo "---"
    if [ "$i" -eq 0 ]; then
        rsync -av --update "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_RESULTS}/$pat" "$DEST/" 2>&1 | tail -5
    else
        rsync -av --update "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_RESULTS}/$pat" "$DEST/" 2>&1 | tail -5 || true
    fi
done

for i in "${!GLOBS[@]}"; do
    pat="${GLOBS[$i]}"
    name_pat="$(basename "$pat")"
    AFTER[$i]=$(find "$DEST" -maxdepth 2 -type d -name "$name_pat" 2>/dev/null | wc -l | tr -d ' ')
done

echo "---"
for i in "${!GLOBS[@]}"; do
    pat="${GLOBS[$i]}"
    delta=$(( AFTER[i] - BEFORE[i] ))
    printf "%-30s before=%s → after=%s (+%s new)\n" "$pat" "${BEFORE[$i]}" "${AFTER[$i]}" "$delta"
done
echo "Local path: $DEST"
