#!/usr/bin/env bash
# verify-catalog-fill.sh — a deterministic check the agent CANNOT fudge.
#
# After authoring/filling a provider's models, run this and PASTE THE OUTPUT
# VERBATIM into your summary. It reads the admin catalog (X-Admin-Key, super_admin)
# and asserts the invariants the author-catalog SKILL.md requires — so "looks good"
# is replaced by PASS/FAIL/INFO facts. Every check here mirrors a SKILL.md rule; if
# you change a rule, change the matching check (consistency is load-bearing).
#
# Usage:
#   SPIDERIQ_ADMIN_API_KEY=... ./verify-catalog-fill.sh <provider> [api_base]
# e.g. ./verify-catalog-fill.sh openai https://spideriq.ai
#
# Exit 1 if any FAIL. Requires curl + jq.

set -euo pipefail
PROVIDER="${1:?usage: verify-catalog-fill.sh <provider> [api_base]}"
API_BASE="${2:-https://spideriq.ai}"
KEY="${SPIDERIQ_ADMIN_API_KEY:?set SPIDERIQ_ADMIN_API_KEY (the platform admin key, X-Admin-Key)}"

json="$(curl -s "$API_BASE/api/v1/admin/gate/catalog/models" -H "X-Admin-Key: $KEY")"
rows="$(echo "$json" | jq --arg p "$PROVIDER" '
  (.models // .data // .) | map(select((.provider // "") == $p))')"
n="$(echo "$rows" | jq 'length')"

fails=0; warns=0
row() { printf '  %-6s %-22s %s\n' "$1" "$2" "$3"; }
echo "── catalog-fill verify · provider=$PROVIDER · $n models ────────────────"
[ "$n" -eq 0 ] && { echo "FAIL — no models found for provider '$PROVIDER'"; exit 1; }

# Per-model invariants (each mirrors a SKILL.md rule).
while IFS= read -r m; do
  id="$(echo "$m" | jq -r '.id')"; mid="$(echo "$m" | jq -r '.model_id')"
  cur="$(echo "$m" | jq -r '.is_curated // false')"
  desc="$(echo "$m" | jq -r '.description // "" | length')"
  ctx="$(echo "$m" | jq -r '.context_window // 0')"
  price="$(echo "$m" | jq -r '.pricing_input // 0')"
  links="$(echo "$m" | jq -r '(.links // []) | length')"
  # RULE: authoring stamps is_curated + a real description.
  if [ "$cur" != "true" ] || [ "$desc" -eq 0 ]; then
    row FAIL "$mid" "not authored (is_curated=$cur, description len=$desc)"; fails=$((fails+1))
  # RULE: a description on a stub row (facts absent) is not a filled model.
  elif [ "$ctx" -eq 0 ] && [ "$(echo "$price==0" | bc -l 2>/dev/null || echo 1)" = "1" ]; then
    row WARN "$mid" "authored but FACTS missing (context=0 & price=0 — run enrichment first)"; warns=$((warns+1))
  # INFO: a suspiciously long description may be copied prose (compose is short).
  elif [ "$desc" -gt 400 ]; then
    row INFO "$mid" "description ${desc} chars — long; confirm it's OUR words, not copied prose"
  else
    row PASS "$mid" "curated · ctx=$ctx · \$${price}/1M in · ${links} link(s)"
  fi
done < <(echo "$rows" | jq -c '.[]')

# RULE: badges are calibration, not a formula — flag monoculture.
dominant="$(echo "$rows" | jq -r '
  [ .[] | (.badges // []) | map(.label) | sort | join("+") ] | group_by(.)
  | map({k: .[0], c: length}) | max_by(.c) | "\(.c)\t\(.k)"')"
dcount="$(echo "$dominant" | cut -f1)"; dset="$(echo "$dominant" | cut -f2-)"
if [ "$n" -ge 3 ] && [ "$dcount" -gt $((n*3/5)) ] && [ -n "$dset" ]; then
  row WARN "badges" "monoculture — $dcount/$n models share identical badges [$dset]"; warns=$((warns+1))
fi

echo "────────────────────────────────────────────────────────────────────────"
echo "RESULT: $((n-fails)) ok / $fails FAIL / $warns WARN  (provider=$PROVIDER)"
if [ "$fails" -gt 0 ]; then
  echo "NOT done — fix FAIL rows, OR paste this report verbatim in your summary's"
  echo "\"what I did NOT verify\" section so the reviewer knows what's incomplete."
  exit 1
fi
echo "OK — paste this report verbatim in your fill summary."
