#!/usr/bin/env bash
# Single-job inspection: squeue + sacct + log tail in one SSH call.
#
# Usage:
#   bash job.sh <jobid>                 # squeue + sacct + last 25 log lines
#   bash job.sh <jobid> --lines 100     # custom log tail size
#   bash job.sh <jobid> --no-log        # skip log tail (squeue/sacct only)
#
# Env (load via cluster-ops.env if present):
#   REMOTE_USER, REMOTE_HOST, REPO_REMOTE   (required)
#   REMOTE_LOG_DIR                          (default ~/$REPO_REMOTE/logs)

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --help short-circuits before env validation so unconfigured users can read it.
for arg in "$@"; do
    case "$arg" in -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
done

[ -f "$SCRIPT_DIR/../cluster-ops.env" ] && . "$SCRIPT_DIR/../cluster-ops.env"

: "${REMOTE_USER:?REMOTE_USER not set — see SETUP.md}"
: "${REMOTE_HOST:?REMOTE_HOST not set — see SETUP.md}"
: "${REPO_REMOTE:?REPO_REMOTE not set — see SETUP.md}"

REMOTE_LOG_DIR="${REMOTE_LOG_DIR:-\$HOME/$REPO_REMOTE/logs}"
LINES=25
NO_LOG=0
JOBID=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --lines) shift; LINES="$1"; shift ;;
        --no-log) NO_LOG=1; shift ;;
        -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)
            if [ -z "$JOBID" ]; then
                JOBID="$1"; shift
            else
                echo "Unknown extra arg: $1" >&2; exit 1
            fi
            ;;
    esac
done

if [ -z "$JOBID" ]; then
    echo "Usage: bash job.sh <jobid> [--lines N] [--no-log]" >&2
    exit 1
fi

case "$JOBID" in
    ''|*[!0-9_]*) echo "ERROR: jobid must be numeric (got: $JOBID)" >&2; exit 2 ;;
esac

ssh "${REMOTE_USER}@${REMOTE_HOST}" "bash -s --" "$JOBID" "$LINES" "$NO_LOG" "$REMOTE_LOG_DIR" <<'REMOTE'
set -eo pipefail
JOBID="$1"; LINES="$2"; NO_LOG="$3"; LOGS_DIR="$4"
LOGS_DIR=$(eval echo "$LOGS_DIR")  # expand ~/$HOME if unexpanded

echo "## Job $JOBID"
echo

echo "### squeue"
sq=$(squeue -j "$JOBID" -o '%.10i %.20j %.8T %.10M %.10L %.16R %.20S' 2>/dev/null || true)
if [ -n "$sq" ] && [ "$(echo "$sq" | wc -l)" -gt 1 ]; then
    echo '```'
    echo "$sq"
    echo '```'
else
    echo "_(not in queue — completed, cancelled, or unknown jobid)_"
fi
echo

echo "### sacct"
echo '```'
sacct -j "$JOBID" \
    --format=JobID,JobName%24,State%12,Elapsed,Start,End,ExitCode,Reason%20 \
    2>/dev/null | head -10
echo '```'
echo

# --- Queue assessment (PENDING only) ---
STATE=$(squeue -j "$JOBID" -h -o '%T' 2>/dev/null | head -1)
if [ "$STATE" = "PENDING" ]; then
    echo "### Queue assessment"

    PRIO=$(sprio -j "$JOBID" -h 2>/dev/null | awk '{print $3}' | head -1)
    echo "- Priority: ${PRIO:-?}"

    GPU_CLASS=$(squeue -j "$JOBID" -h -O 'tres-per-job:64' 2>/dev/null \
        | grep -oE 'gres/gpu:[^:[:space:]]+:' | head -1 | cut -d: -f2)

    if [ -n "$GPU_CLASS" ]; then
        # Same-class pending list, sorted by priority desc. Anchored colon
        # avoids matching rtx_6000 inside rtx_pro_6000.
        SAMECLASS=$(squeue -t PD -h --sort=-p -O 'JobID:14,tres-per-job:36,Reason:24' 2>/dev/null \
            | awk -v cls="$GPU_CLASS" '$2 ~ ("gpu:"cls":")')
        if [ -n "$SAMECLASS" ]; then
            TOTAL=$(echo "$SAMECLASS" | wc -l | tr -d ' ')
            RANK=$(echo "$SAMECLASS" | nl -ba | awk -v jid="$JOBID" '$2 == jid {print $1; exit}')
            echo "- Same-class queue: #${RANK:-?} of $TOTAL pending requesting $GPU_CLASS"

            if [ -n "$RANK" ] && [ "$RANK" -gt 1 ]; then
                AHEAD=$(( RANK - 1 ))
                BR=$(echo "$SAMECLASS" | head -n "$AHEAD" | awk '{print $3}' \
                     | sort | uniq -c | sort -rn \
                     | awk '{printf "%s=%d ", $2, $1}')
                [ -n "$BR" ] && echo "- $AHEAD ahead by REASON: $BR"
            fi
        fi
    fi

    # SLURM StartTime is a best-case lower bound, not a commitment.
    ST=$(squeue -j "$JOBID" -h -O 'StartTime:24' 2>/dev/null | tr -d ' ')
    if [ -n "$ST" ] && [ "$ST" != "Unknown" ] && [ "$ST" != "N/A" ]; then
        NOW=$(date +%s)
        SE=$(date -d "$ST" +%s 2>/dev/null || echo 0)
        D=$(( SE - NOW ))
        if [ "$D" -le 60 ]; then
            ETA="next backfill window (best-case lower bound, not a guarantee)"
        elif [ "$D" -lt 300 ]; then
            ETA="best-case ~$((D/60))m $((D%60))s"
        elif [ "$D" -lt 3600 ]; then
            ETA="best-case ~$((D/60))m"
        elif [ "$D" -lt 86400 ]; then
            ETA="best-case ~$((D/3600))h $(((D%3600)/60))m"
        else
            ETA="best-case ~$((D/86400))d $(((D%86400)/3600))h"
        fi
        echo "- SLURM earliest-slot estimate: $ST → $ETA"
    else
        echo "- SLURM earliest-slot estimate: not yet computed — re-check in 1-2 min"
    fi
    echo
fi

if [ "$NO_LOG" = "0" ]; then
    # Glob covers all log naming patterns ending in -<jobid>.out.
    LOGF=$(ls -t "$LOGS_DIR"/*-"$JOBID".out 2>/dev/null | head -1)
    if [ -n "$LOGF" ]; then
        echo "### Log tail (last $LINES lines)"
        echo "path: \`$LOGF\`"
        echo '```'
        tail -n "$LINES" "$LOGF"
        echo '```'
    else
        echo "### Log tail"
        echo "_(no log file matching $LOGS_DIR/*-$JOBID.out — job hasn't started, or log was cleaned)_"
    fi
fi
REMOTE
