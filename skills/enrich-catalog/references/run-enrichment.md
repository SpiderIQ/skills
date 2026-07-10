# Run an enrichment pass (go get the facts)

Fetch a provider's (or specific models') factual fields from the free stack and fill
them provenance-stamped. This is step 1 of "fill a model"; step 2 (author the copy)
is the `author-catalog` skill.

## Steps

1. **Scope it.** Pick a provider (`provider: "openai"`) or an explicit id list
   (`model_ids: [967, 970]`). Supply EXACTLY ONE — both or neither is a 422. For a
   first pass, a single provider is the natural unit; use `model_ids` to finish a
   provider the per-call cap deferred, or to re-enrich a few rows.

2. **Run the enrich.**

   ```bash
   # CLI
   spideriq gate catalog enrich --provider openai
   spideriq gate catalog enrich --model-ids 967,970,971

   # MCP
   gate_catalog_enrich({ provider: "openai" })
   gate_catalog_enrich({ model_ids: [967, 970, 971] })
   ```

   It runs live web fetches (OpenRouter + LLM-Stats + Wikidata) — **seconds per
   model**. A single provider's active set finishes inside the request budget.

3. **Read the result.** The response carries the aggregate:

   ```
   { "scope": {...},
     "result": { "catalog_rows": 19, "matched": 5, "benchmarks_upserted": 78,
                 "provider_perf_upserted": 13, "links_upserted": 13,
                 "facts_updated": 5, "spec_updated": 5, "skipped_no_match": 14 },
     "deferred": 0 }
   ```

   - `matched` = models that matched a source and got enriched.
   - `spec_updated` = rows whose flat spec (context/max_output/pricing/caps/tools) filled.
   - `skipped_no_match` = rows no source recognized (often a mislabeled/renamed model).
   - **`deferred` > 0** ⇒ the per-call cap (~30) stopped short — re-call, or scope by
     `model_ids`, to finish the rest.

4. **Verify the facts landed** — run the script and paste its output:

   ```bash
   SPIDERIQ_ADMIN_API_KEY=… scripts/verify-enrichment.sh openai
   ```

5. **Hand off to author-catalog.** Enrich fills facts; now author the description /
   badges / links (and the provider editorial) in the `author-catalog` skill. Enrich
   FIRST, author SECOND — a description written before the facts land describes a stub.

## Gotchas

- **Exactly one scope.** `provider` AND `model_ids` together (or neither) → 422.
- **Bounded per call.** A huge provider (openrouter=456, nvidia_nim=203) processes the
  first ~30 and reports the rest `deferred`. Never assume one call covered it.
- **`skipped_no_match` is a signal, not noise.** A model no source recognized is often
  **mislabeled** (e.g. a GLM/Qwen row sitting under `provider='openai'`) or renamed.
  High skip counts ⇒ audit the provider bucket before trusting a fill.
- **Facts refresh; copy is preserved.** Re-running enrich on a curated model updates
  its facts and leaves the authored description/badges untouched (the is_curated guard).
- **Missing ≠ zero.** A field a source didn't return stays null/empty on purpose — do
  not "fix" it by writing a value (HARD-GATE). A delisted model keeps null spec.
- **Cron stays dark.** This is on-demand; it never arms the fleet 6h sweep.

## Verify

- `result.spec_updated` and `benchmarks_upserted` should be > 0 for a provider whose
  models exist on OpenRouter + LLM-Stats. All-zero ⇒ a matching problem (see
  `skipped_no_match`) or a source outage (`source_failures`).
- `scripts/verify-enrichment.sh <provider>` asserts, per model: spec present, at least
  one benchmark row, and provenance (source/attribution) on the fetched rows.
- Spot-check one model in the catalog read (`spideriq gate catalog get <id>`) — confirm
  context/pricing are non-zero and benchmarks are attributed to `llm-stats.com`.
