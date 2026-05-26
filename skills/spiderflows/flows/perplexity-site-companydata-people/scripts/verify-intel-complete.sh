#!/usr/bin/env bash
# verify-intel-complete.sh — audit a finished company-intel run against its stages.
#
# Reads the job aggregate (/jobs/{id}/results) and reports, per stage, whether
# data actually landed — so you don't tell the user "done" when the registry
# missed, no LinkedIn page was found, or zero emails verified. Partial briefs are
# NORMAL for this chain (see learnings/), so empty optional stages are notes, not
# failures; the only hard gap is "the run produced no company record at all".
#
# Deterministic; safe to paste the output.
#
# Usage:
#   SPIDERIQ_PAT="client_id:api_key:api_secret" \
#     ./verify-intel-complete.sh <job_id>
#
# Exit codes: 0 = a company record landed; 1 = no record / not complete;
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

# The aggregate shape varies (single vs batch); this parser is defensive — it
# scans the JSON for the per-stage signals wherever they live.
read -r status companies domain registry linkedin people emails < <(
  echo "$res" | python3 -c '
import sys, json
d = json.load(sys.stdin)

def walk(o):
    # yield every dict in the tree
    if isinstance(o, dict):
        yield o
        for v in o.values():
            yield from walk(v)
    elif isinstance(o, list):
        for v in o:
            yield from walk(v)

status = d.get("status", "?")

# count company records: batch carries a list; single is one record
companies = 0
for node in walk(d):
    if "company" in node and isinstance(node.get("company"), dict):
        companies += 1
companies = companies or (1 if status else 0)

def any_nonempty(*keys):
    for node in walk(d):
        for k in keys:
            v = node.get(k)
            if v:  # non-empty dict/list/str
                return 1
    return 0

domain   = any_nonempty("domain", "final_url")
registry = any_nonempty("registry", "registration_number", "company_registry")
linkedin = any_nonempty("linkedin_company", "linkedin_url", "linkedin_profiles")
people   = any_nonempty("employees", "team_members", "contacts")
emails   = any_nonempty("emails", "emails_found", "emails_verified")

print(status, companies, domain, registry, linkedin, people, emails)
'
)

gap=0
printf 'job %s — status=%s, company_records=%s\n' "$JOB_ID" "$status" "$companies"
[ "${companies:-0}" -gt 0 ] || { echo "  ^ GAP: no company record produced"; gap=1; }
printf '  Discovery  domain/final_url : %s\n' "$([ "$domain" = 1 ] && echo yes || echo no)"
[ "$domain" = 1 ] || echo "  ^ note: no domain discovered (check the company_name / supply a domain hint)"
printf '  Registry   filing           : %s\n' "$([ "$registry" = 1 ] && echo yes || echo no)"
[ "$registry" = 1 ] || echo "  ^ note: empty registry (ok — UK/US/EU only, or stage disabled)"
printf '  LinkedIn   company/people   : %s\n' "$([ "$linkedin" = 1 ] && echo yes || echo no)"
[ "$linkedin" = 1 ] || echo "  ^ note: no LinkedIn record (ok — no page found, or stage disabled)"
printf '  People     contacts         : %s\n' "$([ "$people" = 1 ] && echo yes || echo no)"
printf '  Emails     verified         : %s\n' "$([ "$emails" = 1 ] && echo yes || echo no)"
[ "$emails" = 1 ] || echo "  ^ note: no emails (ok if site had none / verify disabled)"

[ "$status" = "completed" ] || { echo "  ^ note: status is '$status', not 'completed' — poll again"; gap=1; }
exit $gap
