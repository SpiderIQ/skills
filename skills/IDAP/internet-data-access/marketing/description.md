## internet-data-access (IDAP)

Unified read and flag API over all per-client normalized data — businesses, domains, contacts, emails, phones, company registry, and LinkedIn profiles. 7 tools.

### What this skill does

- **`fetchResource`** — fetch a single resource by type and ID, with field projection and optional related-resource includes.
- **`listResources`** — list with cursor pagination, `since` for incremental sync, flag filters, sort/order, source filters.
- **`searchResources`** — full-text search backed by PostgreSQL `tsvector`.
- **`writeFlags`** — add or remove flags on a resource (idempotent, history preserved). Behavioral flags include `qualified`, `rejected`, `do_not_contact`.
- **`batchFetch`** — fetch up to 100 resources per call via `idap://` ref strings.
- **`getStats`** — aggregate stats (total count, flag distribution, source breakdown, last-24h activity) for any resource type.
- **`resolveByExternalId`** — look up a canonical resource by external identifier (place_id, domain, email, url, vat, registration_number, lei, tax_id, linkedin, twitter, source_id). Returns the canonical row if it exists in the caller's normalized data, 404 otherwise.

### Why a separate skill from `scrape-*` and `lead-enrichment`?

The scrape-* skills *discover* data; `lead-enrichment` manages workflow stages on a kanban board. IDAP is the consistent read/flag layer on top of everything already collected — it does NOT trigger new scraping. Use it when you need to:

- Iterate over already-scraped businesses or contacts for downstream work.
- Sync newly-collected records into an external CRM (since-cursor → batchFetch).
- Look up a canonical record from an external ID you already have (e.g. a VAT or LinkedIn URL).
- Flag records as qualified / rejected without going through a kanban board.

### Resource types

`businesses`, `domains`, `contacts`, `emails`, `phones`, `company_registry`, `linkedin_profiles`.

### Typical workflows

- **Incremental CRM sync** — `listResources(since=last_sync)` → `batchFetch(refs)` → write to external system.
- **Qualify-then-act** — `searchResources(q)` → `writeFlags(add=[qualified])` → downstream tools pick up qualified rows only.
- **Resolve-and-load** — agent has a VAT or place_id → `resolveByExternalId` → `fetchResource(id, include=...)` for the full record.
- **Per-tenant reporting** — `getStats(type)` for dashboarding.

### Performance notes

- Batch max is 100 refs per request.
- `since` + `cursor` pagination is keyset-indexed; safe to poll on a 60-second cadence.
- `resolveByExternalId` is backed by partial btree indexes on each identifier column — sub-millisecond lookups even at multi-million-row scale.

### No credit cost

IDAP reads pre-collected data — there's no per-call credit charge. Cost attribution stays with the original scrape/verify/enrich operations that produced the data.
