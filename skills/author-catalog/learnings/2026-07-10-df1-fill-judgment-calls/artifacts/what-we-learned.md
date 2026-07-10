# DF.1 fill — the judgment calls (what a catalog author actually hits)

The DF.1 pilot filled the 5 genuine OpenAI models end-to-end (specs, benchmarks,
provider-perf, links, authored copy, provider editorial) and left the data live for
review. These are the decisions that came up — the institutional knowledge a future
curator agent needs, and the guard rails this skill inherits.

## 1. This skill writes the EDITORIAL half, not the FACTS half

A "fill" is two jobs:

```
  FACTS  (enrichment path)                 EDITORIAL  (this skill)
  ──────────────────────────               ──────────────────────
  context_window, max_output               description, long_description
  pricing_input / pricing_output           tags, badges
  capabilities, supports_tools             sort_order, hidden
  gate_catalog_benchmarks                  reference links (+ provenance)
  gate_catalog_provider_perf               provider editorial (provider_metadata)
        ▲                                          ▲
   OpenRouter / LLM-Stats / Wikidata         author-catalog (X-Admin-Key)
   → discovery sync / curator agent
```

Authoring a description on a row whose `context_window` is still 0 and which has no
benchmarks does **not** make it "filled." Author copy **after** the enrichment pass
has written the facts, and ground the copy in those facts.

## 2. Descriptions are composed from facts, never copied

The whole licensing premise is *facts + OUR words + provenance*. A description built
from structured facts (developer, modality, release, license, context, price) is
provably not a copy. Pasting a vendor's blurb or a Wikipedia paragraph is a licensing
defect — copyright, and Wikipedia is CC-BY-SA share-alike (copyleft). If you only have
prose and no facts, write **less**.

## 3. Missing data is left as a visible gap — never fabricated

- **A delisted model has no primary spec source.** `o1-mini` was dropped from
  OpenRouter, so context/max_output couldn't be fetched. They were left at 0 (a
  visible gap in the report), and pricing was backfilled **per-field from a secondary
  sourced value** (the LLM-Stats provider row, $3/$12) — a sourced fallback, not a
  guess.
- **A source that returns nothing leaves the field empty + flagged.** Wikidata
  resolved **no QID for all 5 models** because it was searched with the catalog
  `display_name`, which for configured rows is the ugly `spidergate_id`
  (`gpt-4o-openai`), not a canonical name. Lineage/website therefore stayed empty —
  flagged in the report, not filled with a bad match. (Fix for the agent: search
  Wikidata with a canonical model name.)

## 4. Self-reported benchmarks are honest to store, but must be labeled

All 78 benchmark rows were the vendor's own published numbers (`self_reported=TRUE`
on the row). Fine to show, but they must be labeled "vendor-reported" — they are not
independent evaluations.

## 5. The provider bucket can be polluted — enumerate the genuine set first

`provider='openai'` had 19 rows, but only 5 were real OpenAI (ids 967–971). The other
14 (66125–66138) were GLM / Qwen / Kimi / MiniMax / Doubao **mislabeled** as OpenAI.
The pilot filled only the genuine 5 and reported the mislabels as a separate
data-integrity bug. A fleet fill that trusts the provider label would corrupt those
rows — always confirm the genuine set before filling.

## Take-away for the future curator agent (DF.2)

- **Automatable:** fetch specs/benchmarks/pricing/perf with provenance; attach the
  discovered reference links.
- **Needs human/LLM authoring:** descriptions (licensing + tone), badges (editorial
  judgment), which canonical doc link to pin.
- **Always:** facts + our words + provenance on every row; leave a gap visible, never
  invent; confirm the genuine model set; label self-reported numbers.

Full per-field source table + the exact source→field recipe:
`docs/external/catalog-fill-pilot-openai-2026-07-10.md` (GateBoard DF.1, PR #2373).
