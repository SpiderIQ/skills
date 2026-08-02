#!/usr/bin/env bash
# verify-maps-complete.sh — audit a finished Maps Search run.
#
# Reads the job results (/jobs/{id}/results) and reports the count of businesses
# and how many carry a website / phone / coordinates — so you can tell the user
# "18 businesses, 15 with a website" instead of guessing. A short/empty list is
# NORMAL (the area may have few matches, or Google served a reduced format), so
# low coverage is a note, not a failure; the only hard gaps are "not complete"
# and "zero businesses".
#
# Deterministic; safe to paste the output.
#
# Usage:
#   SPIDERIQ_PAT="client_id:api_key:api_secret" \
#     ./verify-maps-complete.sh <job_id>
#
# Exit codes: 0 = completed with >=1 business; 1 = not complete / zero results;
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

# The businesses live at data.businesses[]; this parser is defensive about the
# exact nesting (data.businesses, top-level businesses, or data.data).
read -r status query count with_site with_phone with_coords dummy < <(
  echo "$res" | python3 -c '
import sys, json
d = json.load(sys.stdin)

status = d.get("status", "?")
data = d.get("data", d) if isinstance(d.get("data"), dict) else d
biz = data.get("businesses")
if not isinstance(biz, list):
    biz = data.get("data") if isinstance(data.get("data"), list) else []

count = len(biz)
with_site = sum(1 for b in biz if isinstance(b, dict) and b.get("website"))
with_phone = sum(1 for b in biz if isinstance(b, dict) and (b.get("phone") or b.get("phone_e164")))
with_coords = sum(1 for b in biz if isinstance(b, dict) and b.get("coordinates"))
# count businesses carrying the exact compact-format placeholder pair
dummy = sum(1 for b in biz if isinstance(b, dict)
            and b.get("rating") == 4.0 and b.get("reviews_count") == 1024)

print(status, json.dumps(data.get("query", "")), count, with_site, with_phone, with_coords, dummy)
'
)

gap=0
printf 'job %s — status=%s, query=%s\n' "$JOB_ID" "$status" "$query"
printf '  businesses          : %s\n' "$count"
[ "${count:-0}" -gt 0 ] || { echo "  ^ GAP: zero businesses (ok if the area has few matches / Google cooldown — re-run or widen the query)"; gap=1; }
printf '  with website        : %s\n' "$with_site"
printf '  with phone          : %s\n' "$with_phone"
printf '  with coordinates    : %s\n' "$with_coords"
if [ "${dummy:-0}" -gt 0 ]; then
  printf '  ^ note: %s business(es) carry rating=4.0 + reviews_count=1024 — likely COMPACT-format placeholders, not real values\n' "$dummy"
fi

[ "$status" = "completed" ] || { echo "  ^ note: status is '$status', not 'completed' — poll /jobs/$JOB_ID/results again"; gap=1; }
exit $gap
