# Recipe: size a campaign before you submit

A campaign's `filter` decides how many locations it fans out to — and each
location runs a full Maps → Site → Verify (→ VayaPin) pipeline of up to
`max_results` businesses. Get this wrong and one submit launches thousands of
runs. This is the most expensive mistake in the chain.

## The filter matrix

| `filter.mode` | Locations selected | Required field | Cost |
|---|---|---|---|
| `all` | every city in the country (postcodes only if `include_postcodes`) | — | **highest** |
| `cities_only` | every city in the country | — | high |
| `regions` | cities within named admin regions (states) | `admin_regions: [...]` | scoped |
| `regions` + `include_postcodes: true` | **every ZIP** within the named state(s) — one Maps search each | `admin_regions: [...]` (US: exactly one) | deep |
| `city` | one city's ZIPs | `parent_city` | scoped |
| `population` | locations above/below a population band | `min_population` (and/or `max_population`) | scoped |
| `custom` | a hand-picked list | `location_ids: [...]` | exact |

`all` and `cities_only` over a whole country are the runaway modes. `regions`,
`population`, and `custom` are the safe levers.

## Pre-flight estimate (the exact tool — use this first)

Don't guess the location count — ask. `POST /api/v1/jobs/spiderMaps/campaigns/estimate`
takes the same `country_code` + `filter` (+ `max_results` + `workflow`) you'd submit and
returns the exact fan-out **without writing a single row** (pure read, not billed, not a
dispatcher submission):

```bash
curl -X POST "https://spideriq.ai/api/v1/jobs/spiderMaps/campaigns/estimate" \
  -H "Authorization: Bearer $SPIDERIQ_PAT" \
  -H "Content-Type: application/json" \
  -d '{
    "country_code": "DE",
    "filter": { "mode": "regions", "admin_regions": ["Bayern"] },
    "max_results": 100,
    "workflow": { "spidersite": {"enabled": true}, "spiderverify": {"enabled": true}, "vayapin": {"enabled": false} }
  }'
```

Response (`CampaignEstimateResponse`):

| Field | Meaning |
|---|---|
| `total_locations` | locations the campaign fans out to (1 spiderMaps job each) |
| `estimated_businesses` | upper bound = `total_locations × max_results` |
| `stages[]` | per-stage `{service_type, enabled, estimated_jobs}` (spiderMaps / spiderSite / spiderVerify / spiderVayapin) |
| `total_billable_jobs` | sum of `estimated_jobs` across enabled stages |
| `requires_upgrade` | `true` when the location volume exceeds the applicable cap → Proceed/Upgrade decision |
| `volume_cap` | the global per-campaign location backstop (`MAX_CAMPAIGN_LOCATIONS`) |
| `assumptions` | the documented hit-rate / ceiling constants used to derive the counts |

> **Cost is expressed as job COUNTS, not USD** — there is no locally-queryable per-job USD
> price. Counts are the proceed/upgrade signal; `requires_upgrade=true` means narrow the
> filter or upgrade the plan before submitting.

**US ZIP campaigns** (`include_postcodes: true`) are the deep-coverage path — every ZIP
runs as its own Maps search, so a state's `postcode_count` (from
`GET /locations/regions?country_code=US`) is the multiplier. The US must be scoped to
**one state** — an all-US ZIP run is rejected (`422`, the >10K-location cap). See
[state-zip-campaign.md](state-zip-campaign.md).

## Steps

1. **Default is `all`.** If the user didn't narrow it, assume the widest, most
   expensive expansion and narrow before submitting.

2. **Estimate the location count — call `/estimate` (above), don't guess.** A
   country-wide `all`/`cities_only` campaign can be **thousands** of locations — one
   `(country: DE, mode: all)` campaign once fanned to **1,733 locations** and dispatched
   113 worker jobs in 23 seconds. The estimate returns `total_locations` +
   `total_billable_jobs` exactly; if `requires_upgrade` is `true`, narrow or upgrade
   before submitting.

3. **Narrow deliberately**, e.g.:
   ```json
   { "filter": { "mode": "regions",    "admin_regions": ["Bayern", "Hessen"] } }
   { "filter": { "mode": "population", "min_population": 50000 } }
   { "filter": { "mode": "custom",     "location_ids": [101, 102, 103] } }
   ```

4. **If you must run wide, submit then immediately read back `total_locations`**
   from the `201` response. If it exceeds what the user intended, `stop` the
   campaign at once (see [manage-campaign.md](manage-campaign.md)) — a stopped
   campaign halts before most locations dispatch.

## Gotchas

- **`population` mode requires `min_population`**; `custom` requires `location_ids`;
  `regions` requires `admin_regions`. Omitting them → `422`, not a silent wide run.
- **`max_results` is per location** — it multiplies the location count.
- A **single** run (`/lead-search`) is always safe — this gate is campaigns only.

## Verify

- You can state the expected location count *before* submitting.
- After submit, the `total_locations` in the response matches your estimate (±
  the country's location granularity).
- If it doesn't, you `stop`ped before the fan-out completed.
