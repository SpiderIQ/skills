#!/usr/bin/env bash
# verify-bulk-complete.sh — audit a finished bulk lead-sourcing run.
#
# Answers the one question a 200 cannot: did the PIPELINE run, or did the run
# merely echo the purchased seed back at you?
#
# ── WHY THIS SCRIPT READS TWO LEVELS ────────────────────────────────────────
# A bulk run's results live in two places:
#
#   GET /jobs/<parent>/results   → a FUNNEL SUMMARY. screening / cost / children.
#                                  It has NO `businesses` array and never will.
#   data.children.job_ids[]      → one job per surviving lead. Each read through
#                                  the SAME endpoint; THIS is where `businesses` is.
#
# Versions of this script up to 0.10.0 hunted `businesses` on the PARENT and
# printed "FAIL — the run produced no leads" when they did not find it. That was
# a FALSE FAILURE on every healthy bulk run ever audited. This version reads the
# parent for the funnel and follows the children for the leads, and it
# distinguishes the three answers that got collapsed into that one FAIL:
#
#   • the screen kept nothing  → an ANSWER (drop_reasons says why)   → exit 0
#   • leads exist but no stage evidence → a genuine SUSPECT           → exit 1
#   • this payload is not a bulk parent → I looked in the wrong place → exit 2
#
# ── WHY IT DOES NOT TRUST THE STATUS ────────────────────────────────────────
# A failed WindMill flow reports `completed` on every customer surface with a
# full result body (see learnings/2026-08-09-a-completed-flow-can-still-have-
# failed/). So the run is cross-checked against the campaign aggregate, which
# reports stage counts (`sites_completed`, `verifies_completed`) independently
# of whether those stages FOUND anything.
#
# Deterministic; safe to paste the output.
#
# Usage:
#   SPIDERIQ_PAT="client_id:api_key:api_secret" \
#     ./verify-bulk-complete.sh <job_id>
#
#   <job_id> is the PARENT job id from the 202 (not the bulk_job_id) — there is
#   no bulk-specific status route, so the parent job is what carries progress.
#   A CHILD (or any ordinary campaign job) id also works and is audited directly.
#
# Exit codes: 0 = terminal AND the outcome is fully accounted for
#                 (leads with stage evidence, OR a complete zero-kept screen);
#             1 = completed but the outcome is NOT accounted for — suspect;
#             2 = usage/auth error, not yet terminal, or an unrecognised payload.
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
# Soft fetch: a missing/erroring optional endpoint must not abort the audit.
get_soft() { curl -fsS "${auth[@]}" "$1" 2>/dev/null || echo '{}'; }

# 🔴 NO `?format=json` ON ANY URL BELOW. The `format` query param is validated
# against `^(yaml|md)$`, so `format=json` is a 422 SCHEMA_VALIDATION_FAILED — JSON
# is the DEFAULT, reached by omitting the param entirely. Up to 0.10.0 every URL
# here carried `?format=json` and the script therefore died on its FIRST request
# with a generic "request failed", which reads as an auth or outage problem.
# Measured 2026-08-21 against production.

status_json="$(curl -fsS "${auth[@]}" "$BASE/jobs/$JOB_ID/status" 2>/dev/null || true)"
if [ -z "$status_json" ]; then
  echo "ERR: no job found for id: $JOB_ID" >&2
  echo "  If you passed the bulk_job_id from the 202, that is a DIFFERENT identifier" >&2
  echo "  and has no status or results route. Pass the job_id (the PARENT job)." >&2
  exit 2
fi
status="$(echo "$status_json" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("status") or (d.get("data") or {}).get("status") or "?")')"

echo "job_id:  $JOB_ID"
echo "status:  $status"

case "$status" in
  completed|complete) ;;
  failed|error)  echo "RESULT: FAILED — the run did not finish."; exit 2 ;;
  *)             echo "RESULT: not terminal yet (status=$status) — poll again."; exit 2 ;;
esac

res="$(get "$BASE/jobs/$JOB_ID/results")"

# ---------------------------------------------------------------------------
# Classify the payload BEFORE counting anything. Three shapes reach this point,
# and conflating them is the defect this rewrite exists to close.
#
#   parent  — has `screening` and/or `children`. A funnel. No businesses.
#   leaf    — has `businesses`. A child, or an ordinary campaign job.
#   unknown — neither. NOT a failure of the run; a failure of the ADDRESS.
# ---------------------------------------------------------------------------
read -r shape delivered kept dropped reasons fanned truncated campaign nchild stages < <(
  python3 -c '
import sys, json
d = json.load(sys.stdin)
data = d.get("data")
data = data if isinstance(data, dict) else {}

scr = data.get("screening") if isinstance(data.get("screening"), dict) else None
ch  = data.get("children")  if isinstance(data.get("children"), dict)  else None

def walk(o):
    if isinstance(o, dict):
        yield o
        for v in o.values():
            yield from walk(v)
    elif isinstance(o, list):
        for v in o:
            yield from walk(v)

has_biz = any(isinstance(n.get("businesses"), list) for n in walk(d))

if scr is not None or ch is not None:
    shape = "parent"
elif has_biz:
    shape = "leaf"
else:
    shape = "unknown"

scr = scr or {}
ch  = ch or {}
ids = ch.get("job_ids") if isinstance(ch.get("job_ids"), list) else []
dr  = scr.get("drop_reasons") if isinstance(scr.get("drop_reasons"), dict) else {}
stages = [str(x) for x in (data.get("stages_enabled") or []) if isinstance(x, (str, int))]

def n(v):
    return v if isinstance(v, int) else -1

# drop_reasons is squashed to one token so `read` keeps its columns aligned.
reasons = ",".join(f"{k}={v}" for k, v in sorted(dr.items())) or "-"
print(shape,
      n(scr.get("provider_delivered")), n(scr.get("kept")), n(scr.get("dropped")),
      reasons,
      n(ch.get("fanned_out_count")),
      "yes" if ch.get("job_ids_truncated") else "no",
      ch.get("campaign_id") or data.get("campaign_id") or "-",
      len(ids),
      ",".join(stages) if stages else "-")
' <<<"$res"
)

# ---------------------------------------------------------------------------
# Shape: unknown. The address is wrong, or the type is not readable here.
# This is deliberately NOT the "produced no leads" verdict — that conflation is
# precisely what made the old script lie.
# ---------------------------------------------------------------------------
if [ "$shape" = "unknown" ]; then
  jtype="$(python3 -c 'import sys,json; print(json.load(sys.stdin).get("type") or "?")' <<<"$res")"
  echo "type:    $jtype"
  echo
  echo "RESULT: CANNOT AUDIT — this payload carries neither a bulk funnel"
  echo "  (data.screening / data.children) nor a data.businesses array."
  echo "  That is a wrong ADDRESS, not a failed run. Check that \$1 is the PARENT"
  echo "  job_id from the bulk 202 — the bulk_job_id is a different identifier and"
  echo "  has no status or results route of its own."
  exit 2
fi

# ---------------------------------------------------------------------------
# Shape: leaf. A child job or an ordinary campaign job — audit it directly.
# ---------------------------------------------------------------------------
count_contacts() {
  python3 -c '
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
}

if [ "$shape" = "leaf" ]; then
  read -r businesses emails phones verified < <(count_contacts <<<"$res")
  echo "shape:   single job (a bulk CHILD, or an ordinary campaign job)"
  echo "leads:   $businesses"
  echo "emails:  $emails  (verified: $verified)"
  echo "phones:  $phones"
  echo
  if [ "$businesses" -eq 0 ]; then
    echo "RESULT: FAIL — status is completed but this job carries no leads."
    exit 1
  fi
  if [ "$emails" -gt 0 ] || [ "$phones" -gt 0 ]; then
    echo "RESULT: PASS — $businesses lead(s), and contact data is present."
    exit 0
  fi
  echo "RESULT: SUSPECT — $businesses lead(s) but ZERO contact data of any kind."
  echo "  Audit the PARENT job instead: it cross-checks the campaign aggregate,"
  echo "  which reports whether the site stage RAN independently of what it found."
  exit 1
fi

# ---------------------------------------------------------------------------
# Shape: parent. The funnel first — it is the answer more often than the leads are.
# ---------------------------------------------------------------------------
echo "shape:   bulk PARENT (a funnel summary — per-lead rows live in the children)"
echo "screen:  delivered=$delivered  kept=$kept  dropped=$dropped"
[ "$reasons" != "-" ] && echo "reasons: $reasons"
echo "fanout:  fanned_out=$fanned  child_ids_listed=$nchild  truncated=$truncated"
echo "campaign: $campaign"
echo "stages:  enabled=$stages"
echo

if [ "$delivered" -eq -1 ] && [ "$kept" -eq -1 ]; then
  echo "RESULT: SUSPECT — no screening section on a completed parent."
  echo "  screening is omitted when a run never reached the parse stage, so this"
  echo "  is the shape of a run that died before it read the provider's answer."
  echo "  Check the job's error_message and the WindMill flow for $campaign."
  exit 1
fi

# 🔴 kept:0 is an ANSWER, not an error. The caller's own screening floor rejected
# the records; drop_reasons says which floor. Reporting this as a failure is the
# bug this rewrite closes.
if [ "$kept" -eq 0 ]; then
  if [ "$dropped" -gt 0 ]; then
    echo "RESULT: COMPLETE — the run finished and the SCREEN kept 0 of $delivered."
    echo "  This is an ANSWER, not a failure. Reasons: $reasons"
    echo "  Nothing broke and nothing was lost. To keep more records, relax the"
    echo "  screening floor named above and re-run."
    exit 0
  fi
  echo "RESULT: SUSPECT — the provider delivered $delivered and NOTHING was kept,"
  echo "  but nothing was recorded as dropped either. Those numbers do not close."
  exit 1
fi

if [ "$nchild" -eq 0 ]; then
  echo "RESULT: SUSPECT — the screen kept $kept lead(s) but the parent lists NO"
  echo "  child job ids. The fan-out is where per-lead jobs are created, so a"
  echo "  non-zero kept with an empty children.job_ids means fan-out did not run."
  exit 1
fi

# Follow the children. This is the step the old script never took.
child_ids="$(python3 -c '
import sys, json
d = json.load(sys.stdin)
ch = (d.get("data") or {}).get("children") or {}
for i in ch.get("job_ids") or []:
    print(i)
' <<<"$res")"

leads=0; emails=0; phones=0; verified=0; unreadable=0
while IFS= read -r cid; do
  [ -z "$cid" ] && continue
  cres="$(get_soft "$BASE/jobs/$cid/results")"
  if [ "$cres" = "{}" ]; then
    unreadable=$((unreadable + 1))
    continue
  fi
  read -r cb ce cp cv < <(count_contacts <<<"$cres")
  leads=$((leads + cb)); emails=$((emails + ce))
  phones=$((phones + cp)); verified=$((verified + cv))
done <<<"$child_ids"

echo "children read: $nchild  (unreadable: $unreadable)"
echo "leads:   $leads"
echo "emails:  $emails  (verified: $verified)"
echo "phones:  $phones"

# The independent stage witness. `workflow_progress` counts stages that RAN;
# it is the only way to tell "SpiderSite found nothing" from "SpiderSite never ran".
# Its siblings on the same response (total_businesses, locations) read 0/[] for a
# bulk campaign — they are computed through the broken `locations` join. Do not
# use them.
sites_done=-1; verifies_done=-1
if [ "$campaign" != "-" ]; then
  wf="$(get_soft "$BASE/jobs/spiderMaps/campaigns/$campaign/workflow-results")"
  read -r sites_done verifies_done < <(python3 -c '
import sys, json
d = json.load(sys.stdin)
p = d.get("workflow_progress") or {}
def n(v): return v if isinstance(v, int) else -1
print(n(p.get("sites_completed")), n(p.get("verifies_completed")))
' <<<"$wf")
  echo "stages:  sites_completed=$sites_done  verifies_completed=$verifies_done"
fi
echo

if [ "$truncated" = "yes" ]; then
  echo "NOTE: children.job_ids is CAPPED at 100 and this run exceeded it, so the"
  echo "  lead counts above cover only the first $nchild of $fanned. Use the campaign"
  echo "  aggregate for whole-run totals:"
  echo "  $BASE/jobs/spiderMaps/campaigns/$campaign/workflow-results"
  echo
fi

if [ "$leads" -eq 0 ] && [ "$unreadable" -gt 0 ]; then
  echo "RESULT: SUSPECT — $unreadable of $nchild child job(s) could not be read."
  echo "  The parent says $kept lead(s) survived screening, so the leads exist;"
  echo "  this is a READ failure, not an empty run. Retry the child ids."
  exit 1
fi

if [ "$leads" -eq 0 ]; then
  echo "RESULT: SUSPECT — the screen kept $kept but the children carry no leads."
  echo "  Fan-out created the jobs and they are readable, yet none holds a record."
  exit 1
fi

# The provenance assertion. Bulk never asks the provider for contacts
# (contact_enrichment=false), so ANY contact datum had to come from our stages.
if [ "$emails" -gt 0 ] || [ "$phones" -gt 0 ]; then
  echo "RESULT: PASS — $leads lead(s), and contact data is present."
  echo "  Contact data cannot come from the purchased seed (contact enrichment is"
  echo "  never requested), so SpiderSite ran. ${verified} verified email(s) => SpiderVerify ran."
  exit 0
fi

# Zero contact data is NOT automatically suspect — the site stage may have run and
# found nothing. `sites_completed` settles it without guessing.
if [ "$sites_done" -gt 0 ]; then
  echo "RESULT: PASS (no contacts found) — $leads lead(s), zero contact data, but"
  echo "  the campaign aggregate reports sites_completed=$sites_done, so SpiderSite"
  echo "  demonstrably RAN. The sites genuinely carried no contact data. This is a"
  echo "  thin result, not a false green."
  [ "$verifies_done" -eq 0 ] && echo "  (verifies_completed=0 — SpiderVerify had nothing to verify, as expected.)"
  exit 0
fi

# A run with NO enrichment stage enabled cannot produce contact data, so zero is
# the EXPECTED outcome rather than a false green. Measured live on 6dcda426:
# 5 leads, 5 children, sites_completed=0, stages_enabled=[], and correct.
if [ "$stages" = "-" ]; then
  echo "RESULT: COMPLETE (sourcing only) — $leads lead(s), zero contact data, and NO"
  echo "  enrichment stage was enabled for this run (data.stages_enabled is empty)."
  echo "  Zero contact data is the EXPECTED outcome here, not a false green: nothing"
  echo "  was ever asked to look for contacts. To enrich, enable a stage on submit."
  exit 0
fi

case ",$stages," in
  *,spidersite,*) ;;
  *)
    echo "RESULT: COMPLETE (site stage not enabled) — $leads lead(s), zero contact"
    echo "  data. Enabled stages: $stages. SpiderSite is what finds contact data and"
    echo "  it was not part of this run, so zero is the expected outcome."
    exit 0 ;;
esac

echo "RESULT: SUSPECT — $leads lead(s) but ZERO contact data of any kind, and the"
echo "  campaign aggregate reports sites_completed=$sites_done."
echo "  This is what a false green looks like: the seed echoed back with no stage"
echo "  output. Before telling anyone the pipeline ran, check the fan-out campaign"
echo "  ($campaign) has campaign_workflow_jobs > 0."
echo "  SpiderSite WAS enabled for this run (stages_enabled=$stages), so it should"
echo "  have run on every lead. It did not — do not report this run as enriched."
exit 1
