#!/usr/bin/env bash
# Prioritize specific tasks within a multi-cell SLURM array job.
#
# Tasks whose manifest "keep-key" is in your keep-list stay at Nice=0; every
# OTHER pending task gets Nice=$NICE_VALUE (default 500). This is the only
# direction available without admin: negative Nice is admin-only on most
# SLURM installs (typically: nice=100 accepted, nice=-1000 denied for users).
#
# Reads the manifest your submit script writes at:
#   $REMOTE_LOG_DIR/<jobid>.cells.tsv
# Format (tab-separated):
#   idx<TAB>keep-key<TAB>extra1<TAB>extra2…
# See SETUP.md §4 for the contract.
#
# Usage:
#   bash prioritize.sh <jobid> <key1> [<key2> …]   # keep these keys at Nice=0
#   bash prioritize.sh <jobid> --reset             # all cells back to Nice=0
#   bash prioritize.sh <jobid> --dry-run <key>     # show plan without applying
#
# Idempotent — safe to re-run with a different key list. Already-running
# tasks are skipped (Nice has no effect once dispatched).
#
# Env (load via cluster-ops.env if present):
#   REMOTE_USER, REMOTE_HOST, REPO_REMOTE   (required)
#   REMOTE_LOG_DIR                          (default ~/$REPO_REMOTE/logs)
#   NICE_VALUE                              (default 500)

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for arg in "$@"; do
    case "$arg" in -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
done

[ -f "$SCRIPT_DIR/../cluster-ops.env" ] && . "$SCRIPT_DIR/../cluster-ops.env"

: "${REMOTE_USER:?REMOTE_USER not set — see SETUP.md}"
: "${REMOTE_HOST:?REMOTE_HOST not set — see SETUP.md}"
: "${REPO_REMOTE:?REPO_REMOTE not set — see SETUP.md}"

REMOTE_LOG_DIR="${REMOTE_LOG_DIR:-\$HOME/$REPO_REMOTE/logs}"
NICE_VALUE="${NICE_VALUE:-500}"

if [ "$#" -lt 1 ]; then
    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 1
fi

JOBID="$1"; shift
if ! [[ "$JOBID" =~ ^[0-9]+$ ]]; then
    echo "Error: jobid must be a positive integer (got: $JOBID)" >&2
    exit 1
fi
DRY_RUN=0
RESET=0
KEEP_KEYS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --reset) RESET=1; shift ;;
        -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "Unknown option: $1" >&2; exit 1 ;;
        *) KEEP_KEYS+=("$1"); shift ;;
    esac
done

if [ "$RESET" -eq 0 ] && [ "${#KEEP_KEYS[@]}" -eq 0 ]; then
    echo "Error: no keep-keys provided. Pass at least one, or use --reset." >&2
    echo "  Example: bash prioritize.sh $JOBID model-a" >&2
    exit 1
fi

echo "--- prioritize ---" >&2
echo "  jobid:        $JOBID" >&2
if [ "$RESET" -eq 1 ]; then
    echo "  mode:         reset (Nice=0 for all cells)" >&2
else
    echo "  keep@Nice=0:  ${KEEP_KEYS[*]}" >&2
    echo "  deprioritize: everything else (Nice=$NICE_VALUE)" >&2
fi
[ "$DRY_RUN" -eq 1 ] && echo "  DRY-RUN" >&2

# Pipe-joined keep-set; pipes can't appear in keep-keys, and the
# wrap-in-pipes match (`*"|${key}|"*`) prevents prefix bleed.
KEEP_LIST=$(IFS='|'; echo "${KEEP_KEYS[*]}")

ssh "${REMOTE_USER}@${REMOTE_HOST}" \
    "JOBID=$JOBID NICE_VALUE=$NICE_VALUE KEEP_LIST='$KEEP_LIST' \
     RESET=$RESET DRY_RUN=$DRY_RUN LOG_DIR='$REMOTE_LOG_DIR' bash -s" <<'REMOTE'
set -eo pipefail

LOG_DIR=$(eval echo "$LOG_DIR")
manifest="$LOG_DIR/${JOBID}.cells.tsv"
if [ ! -f "$manifest" ]; then
    echo "Error: manifest not found at $manifest" >&2
    echo "(does your submit script write <jobid>.cells.tsv to \$REMOTE_LOG_DIR? see SETUP.md §4)" >&2
    exit 2
fi

# Pending array tasks for this job. -r expands ranges so each task is its
# own row (otherwise SLURM collapses 17389411_[6-9] into one line).
declare -A PENDING
while IFS='|' read -r tid state; do
    [ -n "$tid" ] || continue
    PENDING["$tid"]="$state"
done < <(squeue -h -j "$JOBID" -r -o '%i|%T' 2>/dev/null || true)

if [ "${#PENDING[@]}" -eq 0 ]; then
    echo "No tasks found for job $JOBID (already completed or cancelled?)" >&2
    exit 0
fi

# Walk the manifest, decide Nice per task, optionally apply.
printf 'idx\tarray_id\tkey\textras\tstate\taction\n'
applied=0
skipped_running=0
not_pending=0
while IFS=$'\t' read -r idx key rest; do
    [ -n "$idx" ] || continue
    aid="${JOBID}_${idx}"
    state="${PENDING[$aid]:-MISSING}"

    if [ "$RESET" -eq 1 ]; then
        target_nice=0
    else
        if [[ "|${KEEP_LIST}|" == *"|${key}|"* ]]; then
            target_nice=0
        else
            target_nice="$NICE_VALUE"
        fi
    fi

    case "$state" in
        PENDING)
            action="set Nice=$target_nice"
            if [ "$DRY_RUN" -eq 0 ]; then
                if scontrol update "JobId=$aid" "Nice=$target_nice" 2>/dev/null; then
                    applied=$((applied + 1))
                else
                    action="${action} (FAILED — likely raced to RUNNING)"
                fi
            fi
            ;;
        RUNNING)
            action="skip (already running)"
            skipped_running=$((skipped_running + 1))
            ;;
        MISSING)
            action="skip (not in queue — completed/cancelled)"
            not_pending=$((not_pending + 1))
            ;;
        *)
            action="skip (state=$state)"
            not_pending=$((not_pending + 1))
            ;;
    esac
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$idx" "$aid" "$key" "$rest" "$state" "$action"
done < "$manifest"

echo "---" >&2
if [ "$DRY_RUN" -eq 1 ]; then
    echo "DRY-RUN: no scontrol calls executed." >&2
else
    echo "Applied to $applied pending task(s); skipped $skipped_running running, $not_pending not-in-queue." >&2
fi
REMOTE
