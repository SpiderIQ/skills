#!/usr/bin/env bash
# verify-pipeline-complete.sh — audit a finished run against its expected stages.
#
# Reads the campaign aggregate + IDAP and reports, per stage, whether data
# actually landed — so you don't tell the user "done" when Verify produced zero
# emails or VayaPin published nothing. Deterministic; safe to paste the output.
#
# Usage:
#   SPIDERIQ_PAT="client_id:api_key:api_secret" \
#     ./verify-pipeline-complete.sh <campaign_id> [--expect-vayapin]
#
# Exit codes: 0 = all expected stages produced data; 1 = a gap; 2 = usage/auth error.
set -euo pipefail

BASE="${SPIDERIQ_BASE:-https://spideriq.ai/api/v1}"
PAT="${SPIDERIQ_PAT:-}"
CAMPAIGN_ID="${1:-}"
EXPECT_VAYAPIN=0
[ "${2:-}" = "--expect-vayapin" ] && EXPECT_VAYAPIN=1

if [ -z "$PAT" ] || [ -z "$CAMPAIGN_ID" ]; then
  echo "usage: SPIDERIQ_PAT=... $0 <campaign_id> [--expect-vayapin]" >&2
  exit 2
fi

auth=(-H "Authorization: Bearer $PAT")
get() { curl -fsS "${auth[@]}" "$1" 2>/dev/null || { echo "ERR: request failed: $1" >&2; exit 2; }; }

agg="$(get "$BASE/jobs/spiderMaps/campaigns/$CAMPAIGN_ID/workflow-results?format=json")"

field() { echo "$agg" | python3 -c "import sys,json;print(json.load(sys.stdin).get('$1',0))"; }
status="$(field status)"
biz="$(field total_businesses)"
emails="$(field total_emails_found)"
verified="$(field total_emails_verified)"

# pins via IDAP include (no standalone /idap/pins type)
pins="$(get "$BASE/idap/businesses?campaign_id=$CAMPAIGN_ID&include=pins&limit=500&format=json" \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print(sum(len(b.get('pins',[]) or []) for b in d.get('data',d.get('items',[]))))")"

gap=0
printf 'campaign %s — status=%s\n' "$CAMPAIGN_ID" "$status"
printf '  Maps    businesses        : %s\n' "$biz";      [ "$biz" -gt 0 ]      || { echo "  ^ GAP: no businesses"; gap=1; }
printf '  Site    emails_found      : %s\n' "$emails";   [ "$emails" -gt 0 ]   || echo "  ^ note: site found no emails (ok if site disabled)"
printf '  Verify  emails_verified   : %s\n' "$verified"; [ "$verified" -gt 0 ] || echo "  ^ note: nothing verified (ok if verify disabled)"
printf '  VayaPin pins_published    : %s\n' "$pins"
if [ "$EXPECT_VAYAPIN" = 1 ] && [ "$pins" -eq 0 ]; then echo "  ^ GAP: --expect-vayapin set but 0 pins"; gap=1; fi
if [ "$EXPECT_VAYAPIN" = 0 ] && [ "$pins" -gt 0 ]; then echo "  ^ WARN: $pins pins published though vayapin was not expected"; fi

[ "$status" = "completed" ] || { echo "  ^ note: campaign status is '$status', not 'completed'"; }
exit $gap
