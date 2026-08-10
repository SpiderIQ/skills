#!/usr/bin/env bash
# verify-bulk-complete.sh — audit a finished bulk lead-sourcing run.
#
# Answers the one question a 200 cannot: did the PIPELINE run, or did the run
# merely echo the purchased seed back at you?
#
# A failed WindMill flow reports `completed` on every customer surface with a
# full result body (see learnings/2026-08-09-a-completed-flow-can-still-have-
# failed/). So this script does NOT trust the status code. It asserts on
# evidence the provider seed provably cannot contain: contact data, which only
# SpiderSite can find and only SpiderVerify can verify — because bulk never
# requests contact enrichment from the provider.
#
# Deterministic; safe to paste the output.
#
# Usage:
#   SPIDERIQ_PAT="client_id:api_key:api_secret" \
#     ./verify-bulk-complete.sh <job_id>
#
#   <job_id> is the PARENT job id from the 202 (not the bulk_job_id) — there is
#   no bulk-specific status route, so the parent job is what carries progress.
#
# Exit codes: 0 = completed AND the chain demonstrably ran;
#             1 = completed but NO stage evidence (suspect a false green);
#             2 = usage/auth error or not yet terminal.
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

status_json="$(get "$BASE/jobs/$JOB_ID/status?format=json")"
status="$(echo "$status_json" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("status") or (d.get("data") or {}).get("status") or "?")')"

echo "job_id:  $JOB_ID"
echo "status:  $status"

case "$status" in
  completed|complete) ;;
  failed|error)  echo "RESULT: FAILED — the run did not finish."; exit 2 ;;
  *)             echo "RESULT: not terminal yet (status=$status) — poll again."; exit 2 ;;
esac

res="$(get "$BASE/jobs/$JOB_ID/results?format=json")"

# Walk the envelope defensively: businesses may sit at data.businesses or flat.
read -r businesses emails phones verified < <(
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

rows = []
for node in walk(d):
    b = node.get("businesses")
    if isinstance(b, list) and b:
        rows = b
        break

emails = phones = verified = 0
for r in rows:
    if not isinstance(r, dict):
        continue
    es = r.get("emails") or []
    ps = r.get("phones") or []
    if isinstance(es, list):
        emails += len(es)
        for e in es:
            if isinstance(e, dict) and str(e.get("status", "")).lower() == "valid":
                verified += 1
    if isinstance(ps, list):
        phones += len(ps)

print(len(rows), emails, phones, verified)
'
)

echo "leads:   $businesses"
echo "emails:  $emails  (verified: $verified)"
echo "phones:  $phones"
echo

if [ "$businesses" -eq 0 ]; then
  echo "RESULT: FAIL — status is completed but the run produced no leads."
  exit 1
fi

# The provenance assertion. Bulk never asks the provider for contacts
# (contact_enrichment=false), so ANY contact datum had to come from our stages.
if [ "$emails" -gt 0 ] || [ "$phones" -gt 0 ]; then
  echo "RESULT: PASS — $businesses leads, and contact data is present."
  echo "  Contact data cannot come from the purchased seed (contact enrichment is"
  echo "  never requested), so SpiderSite ran. ${verified} verified email(s) => SpiderVerify ran."
  exit 0
fi

echo "RESULT: SUSPECT — $businesses leads but ZERO contact data of any kind."
echo "  This is what a false green looks like: the seed echoed back with no stage"
echo "  output. Before telling anyone the pipeline ran, check the fan-out campaign"
echo "  (bulk_<bulk_job_id>) has campaign_workflow_jobs > 0."
echo "  It CAN be legitimate (every sourced business genuinely had no website),"
echo "  but do not assume that — confirm it."
exit 1
