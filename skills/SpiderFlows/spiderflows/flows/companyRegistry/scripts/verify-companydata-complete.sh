#!/usr/bin/env bash
# verify-companydata-complete.sh — audit a finished company-registry lookup.
#
# Reads the job output (/jobs/{id}/results) and reports the REAL verdict — not just
# the HTTP/job status. The worker posts every outcome (incl. not-found and
# unsupported-country) to the completion callback, so a missed lookup is still
# status:completed / HTTP 200. The truth is the worker's own data.success (and, for
# vat, data.data.valid). This script reads those and distinguishes:
#   - a real record landed
#   - an empty/not-found result (NORMAL for out-of-coverage; see learnings/)
#   - the job not being complete yet
#
# Mode shapes handled (data = the worker response under the envelope's `data`):
#   search -> data.results[] (+ total_results) ; data.success always true
#   lookup -> data.data{}    ; data.success false on not-found/unsupported-country
#   vat    -> data.data{valid,...} ; data.success always true, verdict is .valid
#
# Deterministic; safe to paste the output.
#
# Usage:
#   SPIDERIQ_PAT="client_id:api_key:api_secret" \
#     ./verify-companydata-complete.sh <job_id>
#
# Exit codes: 0 = complete (record landed OR a legitimately empty/invalid result);
#             1 = not complete yet / job failed; 2 = usage/auth error.
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

# 🔴 NO `?format=json` ON ANY URL BELOW, and do not "tidy" it back in.
# `format` on /jobs/{id}/status and /jobs/{id}/results is validated against
# `^(yaml|md)$`. JSON is the DEFAULT and the ONLY way to ask for it is to NOT ask:
# spelling it out is a 422 SCHEMA_VALIDATION_FAILED. `curl -fsS` renders that as a
# generic "request failed", which reads as auth or an outage — so the real cause is
# invisible. Up to 0.10.1 every URL here carried it and this script therefore died
# on its FIRST request, having verified nothing. Measured against production
# 2026-08-22 (card SDS-27; the same bug in the bulk script was SDS-23).

res="$(get "$BASE/jobs/$JOB_ID/results")"

read -r job_status mode wsuccess records verdict detail < <(
  echo "$res" | python3 -c '
import sys, json
d = json.load(sys.stdin)

job_status = d.get("status", "?")
w = d.get("data") if isinstance(d.get("data"), dict) else {}
wsuccess = w.get("success")

# Infer mode from the worker response shape (no explicit mode field).
if isinstance(w.get("results"), list):
    mode = "search"
    records = len(w["results"])
    verdict = "ok" if records else "empty"
    detail = (w["results"][0].get("name") if records else "no-match").replace(" ", "_") if records else "no-match"
elif isinstance(w.get("data"), dict) and "valid" in w["data"]:
    mode = "vat"
    inner = w["data"]
    records = 1 if inner.get("valid") else 0
    if inner.get("error"):
        verdict = "could-not-validate"
    else:
        verdict = "valid" if inner.get("valid") else "invalid"
    detail = (inner.get("error") or inner.get("company_name") or inner.get("vat_number") or "-").replace(" ", "_")
elif isinstance(w.get("data"), dict):
    mode = "lookup"
    inner = w["data"]
    records = 1
    verdict = "ok"
    detail = (inner.get("name") or "-").replace(" ", "_")
else:
    # success:false lookup (no data.data) or unknown shape
    mode = "lookup" if w.get("country") is not None else "?"
    records = 0
    verdict = "error" if wsuccess is False else "empty"
    detail = (w.get("error") or "-").replace(" ", "_")

print(job_status, mode, wsuccess, records, verdict, detail)
'
)

gap=0
printf 'job %s — job_status=%s, mode=%s, data.success=%s, records=%s\n' \
  "$JOB_ID" "$job_status" "$mode" "$wsuccess" "$records"
printf '  verdict: %s (%s)\n' "$verdict" "$detail"

case "$verdict" in
  ok|valid)
    : ;;  # a real record / valid VAT — nothing to flag
  empty)
    echo "  ^ note: no record (NORMAL — out of UK/US coverage, or no name match; an empty search is worth one retry)" ;;
  invalid)
    echo "  ^ note: VAT genuinely invalid (definitive answer, not an error)" ;;
  could-not-validate)
    echo "  ^ note: VIES could not validate (unsupported country / transient fault) — retry the same number" ;;
  error)
    echo "  ^ note: data.success=false ($detail) — e.g. 'Company not found' or 'Unsupported country' (records are UK/US only)" ;;
esac

if [ "$job_status" != "completed" ]; then
  echo "  ^ job_status is '$job_status', not 'completed' — poll again (or it failed)"
  gap=1
fi

exit $gap
