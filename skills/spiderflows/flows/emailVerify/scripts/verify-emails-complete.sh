#!/usr/bin/env bash
# verify-emails-complete.sh — audit a finished emailVerify run.
#
# Reads the job aggregate (/jobs/{id}/results) and reports the per-status
# breakdown — so you don't tell the user "done, all clean" when half the list
# came back `unknown` (server unreachable / rate-limited), or "verified" when the
# job hasn't actually completed. A high `unknown` count is a NOTE (re-verify
# later), not a failure; the only hard gap is "the run produced no results at
# all" or "status is not completed".
#
# Deterministic; safe to paste the output.
#
# Usage:
#   SPIDERIQ_PAT="client_id:api_key:api_secret" \
#     ./verify-emails-complete.sh <job_id>
#
# Exit codes: 0 = results landed and status=completed;
#             1 = no results / not complete;
#             2 = usage/auth error.
set -euo pipefail

BASE="${SPIDERIQ_BASE:-https://spideriq.ai/api/v1}"
PAT="${SPIDERIQ_PAT:-}"
JOB_ID="${1:-}"

if [ -z "$PAT" ] || [ -z "$JOB_ID" ]; then
  echo "usage: SPIDERIQ_PAT=... $0 <job_id>" >&2
  exit 2
fi

auth=(-H "Authorization: Bearer $PAT")
get() { curl -fsS "${auth[@]}" "$1" 2>/dev/null || { echo "ERR: request failed: $1" >&2; exit 2; }; }

res="$(get "$BASE/jobs/$JOB_ID/results?format=json")"

# The aggregate may be nested under `data` (unified API envelope) or flat; this
# parser is defensive — it finds the SpiderVerifyData node wherever it lives.
read -r status total billable valid invalid risky unknown skipped < <(
  echo "$res" | python3 -c '
import sys, json
d = json.load(sys.stdin)

def walk(o):
    if isinstance(o, dict):
        yield o
        for v in o.values():
            yield from walk(v)
    elif isinstance(o, list):
        for v in o:
            yield from walk(v)

status = "?"
for node in walk(d):
    if "status" in node and isinstance(node.get("status"), str):
        status = node["status"]
        break

# the verify data node carries summary + results
total = billable = 0
summ = {}
for node in walk(d):
    if "results" in node and isinstance(node.get("results"), list) and ("summary" in node or "total" in node):
        total = node.get("total") or len(node.get("results") or [])
        billable = node.get("billable_count") or 0
        summ = node.get("summary") or {}
        break

print(status,
      total,
      billable,
      summ.get("valid", 0),
      summ.get("invalid", 0),
      summ.get("risky", 0),
      summ.get("unknown", 0),
      summ.get("fuzziq_skipped", 0))
'
)

gap=0
printf 'job %s — status=%s, total=%s, billable=%s\n' "$JOB_ID" "$status" "$total" "$billable"
[ "${total:-0}" -gt 0 ] || { echo "  ^ GAP: no verification results produced"; gap=1; }
printf '  valid           : %s\n' "$valid"
printf '  invalid         : %s\n' "$invalid"
printf '  risky           : %s\n' "$risky"
printf '  unknown         : %s\n' "$unknown"
[ "${unknown:-0}" -gt 0 ] && echo "  ^ note: 'unknown' = server unreachable / rate-limited / timed out — re-verify later, not necessarily bad"
printf '  fuzziq_skipped  : %s\n' "$skipped"
[ "${skipped:-0}" -gt 0 ] && echo "  ^ note: skipped = already verified for this client (dedup), not re-billed"

[ "$status" = "completed" ] || { echo "  ^ note: status is '$status', not 'completed' — poll again"; gap=1; }
exit $gap
