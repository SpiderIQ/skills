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
   - `regions` + `admin_regions: ["Bavaria"]` — one state (cities).
   - `regions` + `admin_regions: ["Texas"]` + `include_postcodes: true` — a **US ZIP
     campaign**: every ZIP in the state runs as its own Maps search. The US is too
     large to scrape whole, so scope to **one state** — see
     [state-zip-campaign.md](state-zip-campaign.md) (all-US ZIP runs `422`).
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

## Plan limits — concurrent campaigns + parallel-locations speed

Two plan-tiered limits govern campaigns (enforced server-side on **both** the public
Bearer path and the dashboard path — there is no bypass):

| Tier | Concurrent campaigns | Parallel locations / campaign |
|---|---|---|
| Free | 1 | 1 (sequential) |
| Starter | 1 | 5 |
| Growth | 3 | 15 |
| Pro / Agency | unlimited | 50 |

- **Concurrent-campaign cap** (`max_active_campaigns`) — a hard limit on how many campaigns
  can be `active` at once. Submitting one over the cap returns **`429`** with error code
  **`MAX_CAMPAIGNS_PER_CLIENT`** and an envelope CTA pointing at `/dashboard/plans`:
  ```json
  { "error": {
      "code": "MAX_CAMPAIGNS_PER_CLIENT",
      "message": "You've reached the maximum number of active campaigns for your plan…",
      "suggested_action": "Finish (or stop) a running campaign, or upgrade your plan to run more in parallel.",
      "suggested_url": "/dashboard/plans" } }
  ```
  It is a **finish-or-upgrade** block — no `Retry-After`, no queue. Either `stop` a running
  campaign (see [manage-campaign.md](manage-campaign.md)) or upgrade. The cap also fires a
  `campaign.cannot_start` notification to the account.
- **Parallel-locations "speed dial"** (`max_inflight`) — how many of a campaign's locations
  dispatch *concurrently*. Free runs locations sequentially (1 at a time); higher tiers run
  more in parallel, so the same campaign finishes faster. It changes throughput, not the
  result — no error, just pacing.

## Key fields (`CampaignCreate`)

| Field | Default | Notes |
|---|---|---|
| `search_query` | — | bare term; `query` is a deprecated alias |
| `country_code` | — (required) | ISO 2-letter |
| `filter` | `{mode: "all"}` | **the cost lever** — see cost-check. Fields: `mode` (`all`/`population`/`cities_only`/`regions`/`city`/`custom`), `admin_regions: []`, `parent_city`, `include_postcodes`, `min_population`/`max_population`, `location_ids: []` |
| `filter.include_postcodes` | `false` | opt-in to per-ZIP searches; requires a state/city scope (US ZIP campaigns — see [state-zip-campaign.md](state-zip-campaign.md)) |
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
