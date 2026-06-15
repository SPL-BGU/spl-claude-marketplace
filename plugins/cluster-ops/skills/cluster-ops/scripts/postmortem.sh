#!/usr/bin/env bash
# Postmortem of completed SLURM jobs via `sacct`.
#
# Wall time, MaxRSS, exit code, OOM-Kill flag, derived exit code from children.
# Computes memory headroom across recent jobs and recommends a --mem value to
# drop to (per-job-name peak, since heterogeneous sweeps shouldn't share one).
#
# Output: markdown table + one-line headroom recommendation.
#
# Usage:
#   bash postmortem.sh                              # last 7 days, default name filter
#   bash postmortem.sh --since 2026-04-22           # specific window
#   bash postmortem.sh --jobs 17130166,17130167     # specific job ids
#   bash postmortem.sh --name-prefix exp_           # filter by job-name prefix
#
# Env (load via cluster-ops.env if present):
#   REMOTE_USER, REMOTE_HOST   (required)
#   JOB_NAME_PREFIX            (default empty = no filter)

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for arg in "$@"; do
    case "$arg" in -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
done

[ -f "$SCRIPT_DIR/../cluster-ops.env" ] && . "$SCRIPT_DIR/../cluster-ops.env"

: "${REMOTE_USER:?REMOTE_USER not set — see SETUP.md}"
: "${REMOTE_HOST:?REMOTE_HOST not set — see SETUP.md}"

SINCE=""
JOBS=""
NAME_PREFIX="${JOB_NAME_PREFIX:-}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --since) shift; SINCE="$1"; shift ;;
        --jobs)  shift; JOBS="$1"; shift ;;
        --name-prefix) shift; NAME_PREFIX="$1"; shift ;;
        -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [ -z "$SINCE" ]; then
    SINCE_ARG="--starttime=now-7days"
else
    SINCE_ARG="--starttime=$SINCE"
fi

if [ -n "$JOBS" ]; then
    SCOPE="--jobs=$JOBS"
    NAME_PREFIX=""  # explicit job list bypasses name filter
else
    SCOPE="--user=$REMOTE_USER"
fi

ssh "${REMOTE_USER}@${REMOTE_HOST}" "bash -s --" "$SINCE_ARG" "$SCOPE" "$NAME_PREFIX" <<'REMOTE'
set -eo pipefail
SINCE_ARG="$1"
SCOPE="$2"
NAME_FILTER="$3"

PY=$(cat <<'PY'
import sys, re

def parse_rss(s):
    """sacct MaxRSS like '11329076K', '12.3G', '0' → bytes (int) or None."""
    if not s or s == '0':
        return None
    m = re.match(r'^([\d.]+)([KMGT]?)$', s)
    if not m:
        return None
    val = float(m.group(1))
    mul = {'K': 1024, 'M': 1024**2, 'G': 1024**3, 'T': 1024**4, '': 1}[m.group(2)]
    return int(val * mul)

def fmt_rss(b):
    if b is None: return '-'
    for unit, div in (('TB', 1024**4), ('GB', 1024**3), ('MB', 1024**2), ('KB', 1024)):
        if b >= div:
            return f'{b/div:.1f}{unit}'
    return f'{b}B'

def parse_mem_alloc(tres):
    """AllocTRES like 'cpu=12,mem=48G,node=1,billing=12,gres/gpu=1' → bytes."""
    if not tres: return None
    for part in tres.split(','):
        if part.startswith('mem='):
            return parse_rss(part[4:])
    return None

# sacct emits one line per JobID *and* per JobID.batch / .extern. Merge: keep
# the batch step's MaxRSS but the parent step's State / ExitCode / Elapsed.
jobs = {}
for line in sys.stdin:
    line = line.rstrip('\n')
    if not line: continue
    parts = line.split('|')
    if len(parts) < 10: continue
    jid_raw, jname, state, elapsed, maxrss, reqmem, alloctres, exitcode, dexit, comment = parts[:10]
    is_step = '.' in jid_raw
    parent = jid_raw.split('.')[0]
    rec = jobs.setdefault(parent, {})
    if is_step:
        rss = parse_rss(maxrss)
        if rss is not None and rss > rec.get('maxrss', 0):
            rec['maxrss'] = rss
    else:
        rec.update({
            'jid': parent, 'jname': jname, 'state': state, 'elapsed': elapsed,
            'reqmem': reqmem, 'alloctres': alloctres,
            'exit': exitcode, 'dexit': dexit, 'comment': comment,
        })

print('| job | name | state | elapsed | MaxRSS | --mem | exit | derived | comment |')
print('|---|---|---|---|---|---|---|---|---|')
mem_used_per_job = []
for parent in sorted(jobs):
    r = jobs[parent]
    if 'jid' not in r: continue  # orphan step rows (parent filtered out)
    rss = r.get('maxrss')
    alloc_mem = parse_mem_alloc(r.get('alloctres', ''))
    mem_str = fmt_rss(alloc_mem) if alloc_mem else r.get('reqmem', '-')
    if rss is not None and alloc_mem is not None:
        mem_used_per_job.append((rss, alloc_mem, r['jname']))
    print(f"| {r['jid']} | {r['jname']} | {r['state']} | {r['elapsed']} | "
          f"{fmt_rss(rss)} | {mem_str} | {r['exit']} | {r['dexit']} | "
          f"{r['comment'] or '-'} |")

# Heterogeneous sweeps shouldn't share one --mem; group by jname.
if mem_used_per_job:
    by_name = {}
    for rss, alloc, jname in mem_used_per_job:
        cur = by_name.get(jname)
        if cur is None or rss > cur[0]:
            by_name[jname] = (rss, alloc)
    print()
    print('**Per-job-name peak (right-size --mem):**')
    for jname in sorted(by_name):
        peak_rss, alloc = by_name[jname]
        recommended = int(peak_rss * 1.25 / (1024**3))
        slack = (alloc - peak_rss) * 100 / alloc
        print(f'- `{jname}`: peak {fmt_rss(peak_rss)} of {fmt_rss(alloc)} '
              f'({slack:.0f}% slack) → safe `--mem={recommended}G`')
PY
)

sacct $SCOPE \
      $SINCE_ARG \
      --format=JobID,JobName%30,State%15,Elapsed,MaxRSS,ReqMem,AllocTRES%60,ExitCode,DerivedExitcode,Comment%40 \
      --parsable2 \
      --noheader 2>/dev/null \
    | { if [ -n "$NAME_FILTER" ]; then
          # Match the prefix in field 2 (JobName) for parent rows; let step
          # rows through unconditionally so they merge into MaxRSS later.
          awk -F'|' -v p="$NAME_FILTER" '$1 ~ /\./ || index($2, p) == 1'
        else
          cat
        fi
      } \
    | python3 -c "$PY"
REMOTE
