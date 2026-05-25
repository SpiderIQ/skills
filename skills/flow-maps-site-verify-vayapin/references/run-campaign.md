# Recipe: run across many locations (campaign)

The same search across a set of locations — a country, a region, a population
band. One pipeline runs per location.

## STOP — check cost first

A campaign's `filter` decides how many locations it fans out to. `mode: "all"` or
`"cities_only"` over a whole country can expand to **thousands** of locations. Run
[cost-check.md](cost-check.md) *before* you submit, or narrow the filter.

## Steps

1. **Bare query + structured location.** Unlike single mode, the campaign query is
   *bare* (`"plumbers"`); the location comes from `country_code` + `filter`.
   SpiderIQ builds `"{query} in {location}"` per location itself. **Do not** put a
   city in `search_query` for a campaign.

2. **Pick a filter** (see cost-check for the full matrix):
   - `regions` + `admin_regions: ["Bavaria"]` — one state.
   - `population` + `min_population: 50000` — only larger towns.
   - `cities_only` / `all` — everything; only with eyes open.

3. **Decide stages** — same `workflow` block as single. For a campaign, **VayaPin
   follows your `workflow.vayapin.enabled` exactly** — set it explicitly to the
   value you intend (don't rely on a default). See [vayapin-export.md](vayapin-export.md).

4. **Submit** `POST /api/v1/jobs/spiderMaps/campaigns/submit`:

   ```bash
   curl -X POST "https://spideriq.ai/api/v1/jobs/spiderMaps/campaigns/submit" \
     -H "Authorization: Bearer $SPIDERIQ_PAT" \
     -H "Content-Type: application/json" \
     -d '{
       "search_query": "plumbers",
       "country_code": "DE",
       "filter": { "mode": "regions", "admin_regions": ["Bayern"] },
       "max_results": 100,
       "workflow": {
         "spidersite": { "enabled": true, "mode": "leads" },
         "spiderverify": { "enabled": true },
         "vayapin": { "enabled": false }
       }
     }'
   ```

   Response (`201`, `CampaignResponse`): note the `campaign_id` **and**
   `total_locations`. If `total_locations` is larger than intended, `stop` it now
   (see [manage-campaign.md](manage-campaign.md)).

5. **Watch** via `GET /jobs/spiderMaps/campaigns/{id}/stage-progress` (velocity ETA)
   or the SSE stream.

6. **Read** through IDAP by `campaign_id` — see [read-results.md](read-results.md).

## Key fields (`CampaignCreate`)

| Field | Default | Notes |
|---|---|---|
| `search_query` | — | bare term; `query` is a deprecated alias |
| `country_code` | — (required) | ISO 2-letter |
| `filter` | `{mode: "all"}` | **the cost lever** — see cost-check |
| `max_results` | `100` | 1–500 businesses *per location* |
| `name` | auto | campaign label |
| `workflow` | none → stage defaults | see [per-stage-settings.md](per-stage-settings.md) |

## Gotchas

- **`filter.mode: "all"` is the default.** Submitting with no `filter` over a large
  country is the runaway case. Always set a deliberate filter.
- **`max_results` is per location**, not per campaign — 100 × 1,733 locations is a
  lot of Maps calls.
- **City in `search_query`** (campaign) double-targets — keep it bare.

## Verify

- Response carries a `campaign_id` and a `total_locations` you've sanity-checked.
- `stage-progress` shows locations advancing through Maps → Site → Verify.
- Records appear under `GET /idap/businesses?campaign_id=<id>`.
