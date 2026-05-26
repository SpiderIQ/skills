#!/usr/bin/env bash
# verify-site-complete.sh — audit a finished siteScraper run against what it found.
#
# Reads the job aggregate (/jobs/{id}/results) and reports whether the crawl
# actually landed data — so you don't tell the user "done" when zero pages were
# crawled, or claim team members when AI extraction was never enabled. Empty
# OPTIONAL sections (AI off, no emails on the page) are NOTES, not failures; the
# only hard gaps are "the crawl produced no page" or "status is failed".
#
# Deterministic; safe to paste the output.
#
# Usage:
#   SPIDERIQ_PAT="client_id:api_key:api_secret" \
#     ./verify-site-complete.sh <job_id>
#
# Exit codes: 0 = the crawl landed pages and didn't fail; 1 = no pages / failed /
#             not complete; 2 = usage/auth error.
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

# job status first (the run may not be complete yet)
st="$(get "$BASE/jobs/$JOB_ID/status?format=json")"
job_status="$(echo "$st" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("status","?"))' 2>/dev/null || echo "?")"

res="$(get "$BASE/jobs/$JOB_ID/results?format=json")"

# The results envelope nests the crawl under a few possible keys (data / results /
# top-level). This parser is defensive — it finds the crawl node wherever it lives.
read -r crawl_status pages emails phones socials compendium company team scoring < <(
  echo "$res" | python3 -c '
import sys, json
d = json.load(sys.stdin)

def find_crawl(o):
    # the crawl node has url + pages_crawled; return the first such dict
    if isinstance(o, dict):
        if "pages_crawled" in o or "crawl_status" in o:
            return o
        for v in o.values():
            r = find_crawl(v)
            if r is not None:
                return r
    elif isinstance(o, list):
        for v in o:
            r = find_crawl(v)
            if r is not None:
                return r
    return None

c = find_crawl(d) or {}

def n(x):
    return 1 if x else 0

def listlen(x):
    return len(x) if isinstance(x, list) else 0

crawl_status = c.get("crawl_status", c.get("status", "?"))
pages        = c.get("pages_crawled", 0) or 0

SOCIALS = ["linkedin","twitter","facebook","instagram","youtube","tiktok","github",
           "pinterest","snapchat","reddit","medium","discord","whatsapp","telegram"]
socials = sum(1 for k in SOCIALS if c.get(k))

emails     = listlen(c.get("emails"))
phones     = listlen(c.get("phones"))
compendium = n(c.get("markdown_compendium") or c.get("compendium"))
company    = n(c.get("company_vitals"))
team       = listlen(c.get("team_members"))
scoring    = n(c.get("lead_scoring"))

print(crawl_status, pages, emails, phones, socials, compendium, company, team, scoring)
'
)

gap=0
printf 'job %s — job_status=%s, crawl_status=%s, pages_crawled=%s\n' "$JOB_ID" "$job_status" "$crawl_status" "$pages"

[ "${pages:-0}" -gt 0 ] || { echo "  ^ GAP: zero pages crawled (bad URL? blocked? SPA needing enable_spa?)"; gap=1; }
case "$crawl_status" in
  failed) echo "  ^ GAP: crawl_status=failed"; gap=1 ;;
  partial) echo "  ^ note: crawl_status=partial — some pages failed, the rest are usable" ;;
esac

printf '  Contacts   emails / phones  : %s / %s\n' "$emails" "$phones"
[ "$emails" -gt 0 ] || echo "  ^ note: no emails (the site may expose none — these are EXTRACTED, not verified)"
printf '  Social     profiles found   : %s / 14\n' "$socials"
printf '  Compendium markdown          : %s\n' "$([ "$compendium" = 1 ] && echo yes || echo no)"
printf '  AI         company / team    : %s / %s\n' "$([ "$company" = 1 ] && echo yes || echo no)" "$team"
[ "$company" = 1 ] || echo "  ^ note: no company_vitals (ok — AI is opt-in; enable extract_company_info or mode leads/full)"
printf '  AI         lead_scoring      : %s\n' "$([ "$scoring" = 1 ] && echo yes || echo no)"
[ "$scoring" = 1 ] || echo "  ^ note: no lead_scoring (ok — needs BOTH product_description + icp_description)"

[ "$job_status" = "completed" ] || { echo "  ^ note: job_status is '$job_status', not 'completed' — poll again"; gap=1; }
exit $gap
