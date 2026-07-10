#!/usr/bin/env bash
# verify-enrichment.sh — did the FACTS actually land? A check the agent can't fudge.
#
# After `gate_catalog_enrich`, run this and PASTE THE OUTPUT VERBATIM. It reads the
# admin catalog (X-Admin-Key) and asserts each model in scope now carries the spec
# facts enrichment fetches (context window + list price). "Enriched" is a claim; this
# is evidence. Every check mirrors an enrich-catalog rule.
#
# Usage:
#   SPIDERIQ_ADMIN_API_KEY=... ./verify-enrichment.sh <provider> [api_base]
# e.g. ./verify-enrichment.sh openai https://spideriq.ai
#
# Exit 1 if any FAIL. Requires curl + jq.

set -euo pipefail
PROVIDER="${1:?usage: verify-enrichment.sh <provider> [api_base]}"
API_BASE="${2:-https://spideriq.ai}"
KEY="${SPIDERIQ_ADMIN_API_KEY:?set SPIDERIQ_ADMIN_API_KEY (the platform admin key, X-Admin-Key)}"

json="$(curl -s "$API_BASE/api/v1/admin/gate/catalog/models" -H "X-Admin-Key: $KEY")"
rows="$(echo "$json" | jq --arg p "$PROVIDER" '
  (.models // .data // .) | map(select((.provider // "") == $p))')"
n="$(echo "$rows" | jq 'length')"

fails=0; warns=0; ok=0
row() { printf '  %-6s %-22s %s\n' "$1" "$2" "$3"; }
echo "── enrichment verify · provider=$PROVIDER · $n models ──────────────────"
[ "$n" -eq 0 ] && { echo "FAIL — no models found for provider '$PROVIDER'"; exit 1; }

while IFS= read -r m; do
  mid="$(echo "$m" | jq -r '.model_id')"
  ctx="$(echo "$m" | jq -r '.context_window // 0')"
  price="$(echo "$m" | jq -r '.pricing_input // 0')"
  links="$(echo "$m" | jq -r '(.links // []) | length')"
  has_price="$(echo "$price>0" | bc -l 2>/dev/null || echo 0)"
  if [ "$ctx" -gt 0 ] || [ "$has_price" = "1" ]; then
    row PASS "$mid" "facts present · ctx=$ctx · \$${price}/1M in · ${links} link(s)"; ok=$((ok+1))
  elif [ "$links" -gt 0 ]; then
    # some facts (links) but no spec — likely a delisted/unmatched model.
    row WARN "$mid" "no spec (ctx=0 & price=0) but ${links} link(s) — delisted/secondary-only? leave the gap, don't guess"; warns=$((warns+1))
  else
    row FAIL "$mid" "NO facts (ctx=0, price=0, 0 links) — enrich did not match this row (mislabeled/renamed?)"; fails=$((fails+1))
  fi
done < <(echo "$rows" | jq -c '.[]')

echo "────────────────────────────────────────────────────────────────────────"
echo "RESULT: $ok facts-present / $fails FAIL / $warns WARN  (provider=$PROVIDER)"
if [ "$fails" -gt 0 ]; then
  echo "NOT fully enriched — FAIL rows matched no source (often MISLABELED rows sitting"
  echo "under the wrong provider). Audit + relabel, or scope by model_ids. OR paste this"
  echo "report verbatim in your summary's \"what I did NOT verify\" section."
  exit 1
fi
echo "OK — facts present on every model. Paste this report, then author copy (author-catalog)."
