---
name: enrich-catalog
version: 0.1.0
description: >
  Go GET THE FACTS for the SpiderGate model catalog — fetch a provider's (or
  specific models') factual fields from the free public sources and fill them,
  provenance-stamped: specs + pricing (OpenRouter), benchmarks + per-provider
  performance (LLM-Stats), and lineage (developer/release/license — Wikidata).
  Trigger on: "fill the model catalog", "enrich the gateway catalog", "go get the
  facts for openai", "fetch benchmarks / pricing / specs for a provider", "populate
  a model's context window and price", "refresh a model's benchmarks", "which models
  are missing facts". This is the ADMIN FACTS surface (super_admin, X-Admin-Key) — it
  fetches + writes FACTS, not editorial. Authoring the human COPY (description /
  badges / links) is the sibling `author-catalog` skill; picking a model to use is the
  gateway `model-catalog` read skill.
client: enrich-catalog
client_version: "0.1.0"
category: admin
triggers:
  - fill the model catalog
  - enrich the gateway catalog
  - fetch facts for a provider
  - get benchmarks and pricing for a model
  - populate a model's specs
  - refresh a model's benchmarks
requires_auth: true
requires_brand: false
---

# Enrich the SpiderGate Catalog (go get the facts)

Filling a model in the catalog is two jobs: **fetch the facts**, then **author the
copy**. This skill is the *fetch* half. It runs a scoped, free-stack enrichment pass
over one provider (or an explicit model-id list) and writes the factual fields,
each stamped with `{source, url, retrieved_at, attribution}`.

```
enumerate → gate_catalog_enrich → verify → hand to author-catalog
  (read)      (fetch the facts)    (script)   (write the copy)

gate_catalog_enrich(provider | model_ids) ─▶ specs + pricing  (OpenRouter)
                                          ─▶ benchmarks + perf (LLM-Stats)
                                          ─▶ lineage/facts     (Wikidata)
   writes → gate_model_catalog spec cols · gate_catalog_benchmarks ·
            gate_catalog_provider_perf · gate_catalog_links  (all provenance-stamped)
```

> **AUTH:** `gate_catalog_enrich` carries the platform admin key (`X-Admin-Key`, from
> `SPIDERIQ_ADMIN_API_KEY`) — **not** a client PAT. super_admin, platform-wide (one
> shared catalog). Never echo the key.

## Approach

- **Enrich one provider** — `gate_catalog_enrich(provider: "openai")`. Fetches every
  non-hidden model under that provider (bounded — see the gate). → [references/run-enrichment.md](references/run-enrichment.md)
- **Enrich specific models** — `gate_catalog_enrich(model_ids: [967, 970])`. Use when
  you want exactly a few rows (or to finish a provider the cap deferred).
- **Then author the copy** — enrich fills facts; the description/badges/curated links
  are a separate human/LLM step in `author-catalog`. Enrich FIRST, author SECOND.

<HARD-GATE name="never-fabricate-a-missing-fact">
Every field this writes is **fetched + provenance-stamped, or it stays empty**. A
source that returns nothing (e.g. Wikidata resolves no entity) leaves that fact
**null and visible** — you do NOT fill it from memory. A model delisted from
OpenRouter has **no** context/price from the primary source — leave it null (or
backfill per-field from a secondary *sourced* value like the LLM-Stats provider row),
**never a guess**. Benchmarks are the vendor's own numbers (`self_reported`) — carry
that flag through, never present them as independent. A guessed fact with no
provenance is worse than a visible gap: it looks authoritative and it's wrong.
</HARD-GATE>

## Rules (Non-Negotiable)

**FACTS, NOT COPY.** This skill fetches context/max_output/pricing/capabilities,
benchmarks, provider-perf, and lineage. It does NOT write descriptions, badges, or
tags — that's `author-catalog`. Enrich, verify, THEN author.

**AUTHORED COPY IS PRESERVED.** Enrichment is `is_curated`-safe: a row whose copy a
human authored is never clobbered — only its facts refresh. So you can re-enrich a
curated model without losing the description.

**THE FLEET CRON STAYS DARK.** `gate_catalog_enrich` is on-demand + scoped. It never
arms the fleet-wide 6h enrichment cron. Enrich the models you're about to author, not
the whole catalog by reflex.

**BOUNDED PER CALL.** One call enriches at most ~30 models (it runs live web fetches,
seconds per model). If `result.catalog_rows > result.matched`, the rest were
**deferred** — narrow with `model_ids` or re-call. Never assume one call covered a
huge provider (openrouter, nvidia_nim).

**VERIFY WITH THE SCRIPT.** After enriching, run
[`scripts/verify-enrichment.sh <provider>`](scripts/verify-enrichment.sh) and paste
its output — it asserts the facts actually landed (spec present, benchmarks written,
provenance stamped) as PASS/FAIL/INFO the model can't fudge.

## Decision tree — pick a reference

| The situation… | Read |
|---|---|
| run an enrichment pass (provider or model_ids), read the result, handle deferrals | [references/run-enrichment.md](references/run-enrichment.md) |
| which source feeds which field (the exact recipe) + the known source gaps | [references/source-field-recipe.md](references/source-field-recipe.md) |
| why a source returned nothing / a delisted model / self-reported benchmarks | [learnings/](learnings/) |

## Surface (quick map)

Under `/api/v1/admin/gate`, `X-Admin-Key`, super_admin.

| Do | HTTP | MCP tool | CLI |
|---|---|---|---|
| Fetch facts for a provider / models | `POST /catalog/enrich` | `gate_catalog_enrich` | `spideriq gate catalog enrich --provider … \| --model-ids …` |

## Methods (from client/schema.yaml)

| Method | Does | Reference |
|---|---|---|
| `enrich` | fetch specs/pricing/benchmarks/perf/lineage for a provider or model_ids, provenance-stamped | [references/run-enrichment.md](references/run-enrichment.md) |

## See also

- **`author-catalog`** (this package) — the WRITE-the-copy half. After you enrich,
  author descriptions/badges/links + provider editorial there. Enrich → author is the
  full "fill a model" flow.
- **`model-catalog`** (`@spideriq/gateway-skills`) — the client READ surface that
  CONSUMES what you enrich (pick a model by benchmark/price).
- `learnings/` — the DF.1 pilot's judgment calls (delisted model, empty source,
  self-reported benchmarks, polluted provider bucket). Starting points, not ground
  truth — verify against current code.
- **Not this skill:** writing a model's description/badges is `author-catalog`;
  changing which model an alias routes to is `manage-routing`; sending completions is
  `use-the-gateway`.
