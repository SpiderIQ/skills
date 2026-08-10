# Recipe: bulk or campaign? (read this first)

Both produce the same thing — verified business leads in the tenant's account,
in the **same result envelope**. They differ in *where the breadth comes from*
and *what you pay for it*. Picking wrong is not a correctness bug; it is a cost
and latency bug, and it is not cheap to undo.

```
CAMPAIGN                                   BULK
one Maps search PER LOCATION               one PROVIDER job for ALL queries x locations
  Berlin   → SpiderMaps → n leads            ["plumbers","roofers"] x ["Berlin","Hamburg"]
  Hamburg  → SpiderMaps → n leads               ↓  one flat result set, bought once
  Munich   → SpiderMaps → n leads               ↓  exact-key dedup
       ↓ fan out per LOCATION                    ↓ fan out per LEAD
  Site → Verify → VayaPin                    Site → Verify → VayaPin   (identical)
```

## Pick with this

| The user wants… | Use | Why |
|---|---|---|
| one city, one search | `searchLeads` | fastest, always safe on cost |
| a country/region swept by our own location DB, with per-location progress and retry | `createCampaign` | you get `total_locations`, per-location status, `retryLocation` |
| a large flat list across many terms x many places, bought in one go | **`sourceLeadsBulk`** | one purchase, one dedup pass, no per-location machinery |
| coverage of places our location DB does not model well | **`sourceLeadsBulk`** | you supply the geo labels; nothing is expanded from our DB |
| to re-run a *failed* slice of a previous run | `createCampaign` + `retryFailedLocations` | bulk has no per-location retry — a failed bulk run is re-bought |

## The three differences that actually bite

**1. Bulk has no per-location retry.** A campaign models each location as a row
you can inspect, stop, and retry. A bulk run is *one purchase*: if the provider
returns thin results for one of your labels, there is no `retryLocation` — you
submit a new run for that label and pay again. Prefer a campaign when the user
will want to iterate location-by-location.

**2. Bulk dedups; a campaign does not dedup across locations.** Bulk applies an
exact-key dedup over the whole flat result set before fan-out (`place_id` for
`google_maps`), so a business that a neighbouring city's search also returned is
fanned out **once**. Campaigns fan out per location and can hand you the same
business twice if two locations overlap.

**3. Bulk's breadth is multiplicative and paid up front.** `queries x geo labels`
is the search count, and the whole thing is bought before anything is enriched.
5 queries x 20 labels is **100 searches in one purchase**. A campaign spends
incrementally and can be stopped mid-flight; a bulk purchase cannot be unbought.
See [cost-and-limits.md](cost-and-limits.md).

## What is identical (so don't rebuild it)

- **The downstream chain.** Site → Verify → VayaPin, same workers, same
  `workflow` config shape (`WorkflowConfig` verbatim).
- **The result envelope.** Verified live against two campaign runs: 10/10
  identical top-level keys, 4/4 identical `data` keys
  (`businesses`, `metadata`, `query`, `results_count`), and 24/24 identical
  business field names. Anything that reads campaign results reads bulk results
  unchanged. Only `metadata` differs, by design — it carries bulk provenance
  instead of scrape knobs.
- **How you read results.** Same `getJobResults` / IDAP by campaign id. See
  [read-results.md](read-results.md).

## Verify you chose right

- User said "one city" → you are not here; use `searchLeads`.
- User will want per-location progress/retry → `createCampaign`.
- User wants breadth now, in one purchase, and accepts no per-location retry →
  `sourceLeadsBulk`.
