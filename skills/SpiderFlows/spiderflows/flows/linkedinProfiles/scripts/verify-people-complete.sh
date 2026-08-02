#!/usr/bin/env bash
# verify-people-complete.sh — audit a finished linkedinProfiles run against its mode.
#
# Reads the job aggregate (/jobs/{id}/results) and reports, for the mode that ran,
# whether people data actually landed — so you don't tell the user "done" when a
# profile was private, a search returned no hits, or a company page had no public
# employees. Empty payloads are NORMAL for this flow (see learnings/), so an empty
# optional result is a note, not a failure; the only hard gap is "the run isn't
# complete" or "no record of any kind came back".
#
# Deterministic; safe to paste the output.
#
# Usage:
#   SPIDERIQ_PAT="client_id:api_key:api_secret" \
#     ./verify-people-complete.sh <job_id>
#
# Exit codes: 0 = a result landed (even if empty-but-complete); 1 = not complete;
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

# The aggregate shape varies by mode; this parser is defensive — it scans the JSON
# for the per-mode signals wherever they live (top-level or nested under data/results).
read -r status mode count empty < <(
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

status = d.get("status", "?")

mode = "?"
for node in walk(d):
    m = node.get("mode")
    if m in ("profile", "search", "company"):
        mode = m
        break

# count the people that came back, per mode
count = 0
have = 0   # did the mode-appropriate container exist at all?
for node in walk(d):
    if mode == "profile":
        p = node.get("profile")
        if isinstance(p, dict):
            have = 1
            if p.get("linkedin_url") or p.get("full_name"):
                count = 1
    elif mode == "search":
        pr = node.get("profiles")
        if isinstance(pr, list):
            have = 1
            count = max(count, len(pr))
    elif mode == "company":
        emp = node.get("employees")
        if isinstance(emp, list):
            have = 1
            count = max(count, len(emp))
        ec = node.get("employees_count")
        if isinstance(ec, int):
            have = 1
            count = max(count, ec)

empty = 0 if count > 0 else 1
print(status, mode, count, empty)
'
)

gap=0
printf 'job %s — status=%s, mode=%s, people=%s\n' "$JOB_ID" "$status" "$mode" "$count"

case "$mode" in
  profile)
    printf '  profile record : %s\n' "$([ "$count" -gt 0 ] && echo yes || echo no)"
    [ "$empty" = 0 ] || echo "  ^ note: empty profile (ok — profile may be private/closed)"
    ;;
  search)
    printf '  profiles found : %s\n' "$count"
    [ "$empty" = 0 ] || echo "  ^ note: no search hits (ok — niche query / thin SERP coverage; broaden it)"
    ;;
  company)
    printf '  employees      : %s\n' "$count"
    [ "$empty" = 0 ] || echo "  ^ note: no employees (ok — no public roster / tiny company / check the company URL)"
    ;;
  *)
    echo "  ^ GAP: could not determine mode from the result"; gap=1
    ;;
esac

[ "$status" = "completed" ] || { echo "  ^ note: status is '$status', not 'completed' — poll again"; gap=1; }
exit $gap
