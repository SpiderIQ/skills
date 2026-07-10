# The source → field recipe (which source feeds which field)

`gate_catalog_enrich` runs the free-stack mapping below. Every fetched row carries
`{source, source_url, attribution, retrieved_at}`. We store **facts + provenance** —
never a source's prose (the description/copy is authored separately, from these facts,
in `author-catalog`).

## The mapping

| Field group | Source | How | Written to |
|---|---|---|---|
| context_window, max_output, modality, tools | **OpenRouter API** | `GET /api/v1/models` (public; ToS bars HTML-scraping) | `gate_model_catalog` spec cols |
| list pricing (in/out per 1M) | **OpenRouter** | `/models` pricing ×1e6 | `gate_model_catalog.pricing_*` |
| per-provider pricing + perf (tokens/s, ttft, uptime) | **OpenRouter** + **LLM-Stats** | OR `/endpoints` + LLM-Stats `providers[]` | `gate_catalog_provider_perf` |
| benchmarks (name/score/scale + normalized_score) | **LLM-Stats** (+ OR design-arena Elo) | `api.zeroeval.com/leaderboard/models/{id}` → `benchmarks[]` | `gate_catalog_benchmarks` |
| developer, release_date, license | **LLM-Stats**, cross-checked by **Wikidata** | LLM-Stats facts → `owned_by`; Wikidata claims | `gate_model_catalog.owned_by` + facts |
| lineage (predecessor/successor), official website | **Wikidata** (CC0) | `wbsearchentities` → `EntityData` → `wbgetentities` | `gate_catalog_links` (website) + facts |

Attribution stored per source: OpenRouter → `OpenRouter API`; LLM-Stats →
`Source: llm-stats.com (https://llm-stats.com)`; Wikidata → `Source: Wikidata (CC0)`.

## Safe to fully automate (this skill does it)

Specs, pricing, provider-perf, benchmarks, and the developer/release/license facts —
all fetched with provenance, no human judgment. Re-runnable and idempotent (upserts).

## NOT automated here (→ author-catalog, human/LLM)

Descriptions, `long_description`, badges, editorial tags, and which canonical doc link
to pin — those are composed from these facts by a human or an LLM in `author-catalog`,
because they're editorial + carry the licensing rule (OUR words, never copied prose).

## Known source gaps (handle, don't fabricate)

1. **Wikidata resolves off the model NAME.** If the catalog `display_name` is an ugly
   internal id (e.g. `gpt-4o-openai`, the spidergate_id), `wbsearchentities` finds no
   entity and lineage/website come back empty. That's a **visible gap**, not a value to
   invent. (Fix path: feed a canonical name — a future enrichment improvement.)
2. **A delisted model has no OpenRouter spec.** OpenRouter drops deprecated models
   (e.g. `o1-mini`), so context/max_output/list-price aren't fetchable from the primary
   source. Leave them null, or backfill pricing **per-field** from the LLM-Stats
   provider row (a *sourced* value) — never a guess.
3. **Benchmarks are self-reported.** LLM-Stats' `benchmarks[]` for a closed vendor are
   the vendor's own published numbers (`self_reported=TRUE` on the row). Honest to
   store; must be labeled vendor-reported, not independent.
4. **The flat spec cols carry no per-field provenance columns.** Their provenance is
   the re-fetchable OpenRouter payload + this recipe; the per-provider pricing in
   `gate_catalog_provider_perf` IS fully stamped.
5. **A provider bucket can be polluted.** Some `provider` values contain mislabeled
   rows (models that aren't that provider). They show up as `skipped_no_match` — audit
   + relabel before trusting a provider-wide fill.

See `learnings/` for the DF.1 pilot where each of these first surfaced.
