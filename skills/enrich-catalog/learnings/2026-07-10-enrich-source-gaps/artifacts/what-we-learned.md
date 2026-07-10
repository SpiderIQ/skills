# Enrichment source gaps — handle, never fabricate

`gate_catalog_enrich` fetches facts from three free sources. The DF.1 OpenAI pilot ran
the whole mapping by hand and proved it works — and surfaced the gap in each source a
curator must handle. The rule through all of them: **a fact is fetched + provenance-
stamped, or it stays null. A guess with no provenance is worse than a visible gap.**

## The gaps

1. **Wikidata resolves off the model NAME.** It searches `wbsearchentities` with the
   model name. If the catalog `display_name` is an ugly internal id (the `spidergate_id`,
   e.g. `gpt-4o-openai`), it finds no entity → lineage / official-website come back
   empty for the whole provider. Leave the gap; don't invent lineage. (Improvement path:
   search a canonical name, not the raw display_name.)

2. **A delisted model has no OpenRouter spec.** OpenRouter drops deprecated models
   (`o1-mini` was gone at pilot time), so context/max_output/list-price aren't fetchable
   from the primary source. Leave them null, or backfill pricing **per-field** from the
   LLM-Stats provider row (a *sourced* value). Never fill context from memory.

3. **Benchmarks are self-reported.** For a closed vendor, LLM-Stats' `benchmarks[]` are
   the vendor's own published numbers (`self_reported=TRUE`). Store them, but they must
   read as vendor-reported, not independent evaluations.

4. **The flat spec cols are facts the sync usually owns.** The original B.1 enrichment
   wrote side-tables + `owned_by` but NOT `context_window`/`max_output`/`pricing_*`.
   DF.2 folds those in, COALESCE-guarded (a sync/probe value wins when already set), so
   stub rows finally get their specs.

5. **A provider bucket can be polluted.** In the pilot, 14 rows under
   `provider='openai'` were actually GLM/Qwen/Kimi/MiniMax/Doubao — mislabeled. They
   come back as `skipped_no_match` (no source recognizes them under that provider).
   A high `skipped_no_match` is a data-integrity signal — audit + relabel before you
   trust a provider-wide fill.

## The shape of a good enrichment

```
enumerate → gate_catalog_enrich → verify (script) → author-catalog (copy)
```

- Enrich fills FACTS; the description/badges/links are a separate authored step.
- It's `is_curated`-safe: re-enriching a curated model refreshes facts, keeps the copy.
- On-demand + bounded (~30 models/call; `deferred = catalog_rows - matched`). Never
  arms the fleet cron.
- Verify with `scripts/verify-enrichment.sh <provider>` and paste the output — don't
  claim "enriched" by eye.

Full per-field trace + the exact recipe: DF.1 report
`docs/external/catalog-fill-pilot-openai-2026-07-10.md` (§3 judgment calls, §4 recipe).
