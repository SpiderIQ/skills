#!/usr/bin/env bash
# verify-internal-complete.sh — audit a finished INTERNAL enrichment run.
#
# 🔴 READ THIS BEFORE COPYING THE BULK SCRIPT'S LOGIC. The sibling
# `flows/bulkLeadSourcing/scripts/verify-bulk-complete.sh` asserts that ANY
# contact datum proves the chain ran, because a PURCHASED seed provably cannot
# contain contacts. **That argument is false here and copying it would build a
# gate that passes on a run which did nothing.**
#
# An internal run's seed is the tenant's OWN rows. They may already carry
# emails, phones and crawls — that is frequently why they were selected. So
# "emails > 0" is consistent with a perfect run AND with a run that failed
# instantly and echoed the seed back. It cannot distinguish them, and a check
# that cannot distinguish its two outcomes is not a check.
#
# What DOES distinguish them is a DELTA. The selection was sized on Gate 2:
# leads still MISSING at least one requested stage. If the chain really ran,
# those leads now HAVE that stage's output, so re-counting eligibility for the
# SAME spec must return a SMALLER number. A false green leaves it unchanged.
#
#   before (at select time):  N eligible
#   after  (this script):     M eligible
#   chain ran  <=>  M < N
#
# The re-count is free and writes nothing, which is why this is affordable.
#
# Usage:
#   SPIDERIQ_PAT="client_id:api_key:api_secret" \
#     ./verify-internal-complete.sh <job_id> <eligible_before> <stages> [filter.json]
#
#     <job_id>            the PARENT job id from the 202 (not bulk_job_id)
#     <eligible_before>   eligible_leads as reported by `bulk-source select`
#     <stages>            the SAME comma-separated stage list you selected with
#     [filter.json]       the SAME filter file, for a corpus_query run.
#                         Omit for unenriched_run and pass --campaign/--job via
#                         CAMPAIGN_ID / JOB_ID env vars instead.
#
# ⚠️ The stage list and the filter MUST be the ones the selection was created
# with. A re-count against a different spec is a different question, and it
# would answer it confidently.
#
# Exit codes: 0 = terminal AND eligibility demonstrably fell (the chain ran)
#             1 = terminal but eligibility did NOT fall (suspect a false green)
#             2 = usage/auth error, or not yet terminal
set -euo pipefail

BASE="${SPIDERIQ_BASE:-https://spideriq.ai/api/v1}"
PAT="${SPIDERIQ_PAT:-}"
JOB_ID="${1:-}"
BEFORE="${2:-}"
STAGES="${3:-}"
FILTER_FILE="${4:-}"

if [ -z "$PAT" ] || [ -z "$JOB_ID" ] || [ -z "$BEFORE" ] || [ -z "$STAGES" ]; then
  echo "usage: SPIDERIQ_PAT=... $0 <job_id> <eligible_before> <stages> [filter.json]" >&2
  exit 2
fi

case "$BEFORE" in
  ''|*[!0-9]*) echo "ERR: <eligible_before> must be an integer (got '$BEFORE')" >&2; exit 2 ;;
esac

auth=(-H "Authorization: Bearer $PAT" -H "Content-Type: application/json")

# 🔴 NO `?format=json` ON ANY URL BELOW. The `format` query param on
# /jobs/{id}/status and /jobs/{id}/results is validated against `^(yaml|md)$`, so
# naming JSON is a 422 SCHEMA_VALIDATION_FAILED — and `curl -fsS` renders that as a
# bare failure, which reads like a bad PAT or an outage rather than a bad URL. JSON
# is the DEFAULT, reached by OMITTING the param entirely. This script shipped with
# the param because it was written before SDS-23/SDS-27 swept the other eight
# scripts; the CI guard that globs all 16 is what caught it here.

status_json="$(curl -fsS "${auth[@]}" "$BASE/jobs/$JOB_ID/status" 2>/dev/null)" || {
  echo "ERR: could not read job status — check the PAT and the job_id." >&2; exit 2; }

status="$(printf '%s' "$status_json" | python3 -c \
  'import sys,json; d=json.load(sys.stdin); print(d.get("status") or (d.get("data") or {}).get("status") or "?")')"

echo "job_id:            $JOB_ID"
echo "status:            $status"

case "$status" in
  completed|complete) ;;
  failed|error) echo "RESULT: FAILED — the run did not finish."; exit 2 ;;
  *)            echo "RESULT: not terminal yet (status=$status) — poll again."; exit 2 ;;
esac

# Rebuild the SAME question the selection was sized with.
body="$(
  STAGES="$STAGES" FILTER_FILE="$FILTER_FILE" \
  CAMPAIGN_ID="${CAMPAIGN_ID:-}" JOB_SCOPE="${JOB_ID_SCOPE:-}" \
  python3 - <<'PY'
import json, os
body = {"stages": [s.strip() for s in os.environ["STAGES"].split(",") if s.strip()]}
ff = os.environ.get("FILTER_FILE") or ""
if ff:
    with open(ff) as fh:
        body["filter"] = json.load(fh)
    body["source_kind"] = "corpus_query"
else:
    body["source_kind"] = "unenriched_run"
    if os.environ.get("CAMPAIGN_ID"):
        body["campaign_id"] = os.environ["CAMPAIGN_ID"]
    if os.environ.get("JOB_SCOPE"):
        body["job_id"] = os.environ["JOB_SCOPE"]
print(json.dumps(body))
PY
)"

count_json="$(curl -fsS "${auth[@]}" -X POST \
  "$BASE/dashboard/bulk-lead-sourcing/corpus/count" -d "$body" 2>/dev/null)" || {
  echo "ERR: the re-count call failed. Without it this script has no evidence —" >&2
  echo "     do NOT read that as a pass." >&2; exit 2; }

read -r matched after < <(printf '%s' "$count_json" | python3 -c \
  'import sys,json; d=json.load(sys.stdin); print(d.get("matched_leads",-1), d.get("eligible_leads",-1))')

echo "eligible before:   $BEFORE"
echo "eligible now:      $after   (of $matched matched)"
echo

if [ "$after" -lt 0 ]; then
  echo "RESULT: INCONCLUSIVE — the re-count did not return an eligible_leads field."
  exit 2
fi

if [ "$after" -lt "$BEFORE" ]; then
  echo "RESULT: PASS — eligibility fell by $((BEFORE - after))."
  echo "  Those leads now carry output for at least one requested stage, which the"
  echo "  seed did not have when the selection was sized. The chain ran."
  [ "$after" -gt 0 ] && echo "  NOTE: $after still eligible — a partial run, or leads the stages could not help."
  exit 0
fi

echo "RESULT: SUSPECT — status is '$status' but eligibility did not fall ($BEFORE -> $after)."
echo "  This is exactly what a false green looks like on an internal run: a flow that"
echo "  reported completed while producing no stage output. Contact data being present"
echo "  proves NOTHING here — the seed is the tenant's own rows and may have carried it"
echo "  all along."
echo "  Check the fan-out campaign (bulk_<bulk_job_id>) has campaign_workflow_jobs > 0"
echo "  before telling anyone this run worked."
echo "  It CAN be legitimate — e.g. every selected lead genuinely had no website for"
echo "  SpiderSite to crawl — but confirm it, do not assume it."
exit 1
