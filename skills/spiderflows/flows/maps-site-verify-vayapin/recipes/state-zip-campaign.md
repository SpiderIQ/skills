# Recipe: US ZIP campaign — "state = country" (single-state, every ZIP its own search)

A US city is one Maps search → Google's ~120-result cap (a metro of millions still
returns ~120). To go deep in the US, run **every ZIP code as its own Maps search**.
The US is too large to scrape whole, so the **state is the selection unit**: pick
**one** state, turn on postcodes, and the campaign fans out to one search per ZIP in
that state.

> **The model:** treat each US state like its own country. One campaign = one state.
> "All of US" is **not** selectable for a ZIP run — the API rejects it (`422`, the
> >10,000-location volume cap). This is by design, not a limit to work around.

## Steps

1. **Discover the state names.** The `admin_regions` value must be an exact state
   name. List them (each carries a `city_count` and a `postcode_count` so you can
   size the run first):

   ```bash
   curl -s -H "Authorization: Bearer $SPIDERIQ_PAT" \
     "https://spideriq.ai/api/v1/locations/regions?country_code=US"
   # → { "regions": [ { "region": "Texas", "city_count": 1746,
   #                    "postcode_count": 2645, "location_count": 4391 }, ... ] }
   ```

   A state's **`postcode_count` ≈ how many Maps searches the ZIP run fans out into**
   — size it before launching (Texas ~2,645 ZIP searches × `max_results`).

   (`GET /api/v1/locations/selectable-units` returns the same states merged with real
   countries as a flat typeahead — "Florida" sits beside "Germany" — for pickers.)

2. **Build the filter — exactly ONE state, postcodes ON:**

   ```json
   { "filter": { "mode": "regions", "admin_regions": ["Texas"], "include_postcodes": true } }
   ```

   - `mode: "regions"` + **one** state in `admin_regions`.
   - `include_postcodes: true` flips the run from cities-only to **postcodes-only**
     (every ZIP its own search). Without it, a `regions` campaign is cities-only
     (the old behavior — unchanged).
   - Omit the state, or list more than one, or aim at the whole US → **`422`**.

3. **Submit** (bare query; location comes from `country_code: "US"` + the filter):

   ```bash
   curl -X POST "https://spideriq.ai/api/v1/jobs/spiderMaps/campaigns/submit" \
     -H "Authorization: Bearer $SPIDERIQ_PAT" -H "Content-Type: application/json" \
     -d '{
       "search_query": "plumbers",
       "country_code": "US",
       "filter": { "mode": "regions", "admin_regions": ["Texas"], "include_postcodes": true },
       "max_results": 100,
       "workflow": { "spidersite": { "enabled": true, "mode": "leads" },
                     "spiderverify": { "enabled": true },
                     "vayapin": { "enabled": false } }
     }'
   ```

   Read `total_locations` from the `201` — it should ≈ the state's `postcode_count`.
   If it's bigger than you intended, `stop` it now (see [manage-campaign.md](manage-campaign.md)).

4. **One city instead of a whole state?** Use `mode: "city"` + `parent_city` (implies
   postcodes — just that city's ZIPs):

   ```json
   { "filter": { "mode": "city", "parent_city": "Austin", "admin_regions": ["Texas"] } }
   ```

5. **Watch + read** as any campaign — `stage-progress` / SSE, then IDAP by
   `campaign_id` ([read-results.md](read-results.md)).

## Convenience surfaces

- **CLI:** `spideriq locations regions -c US` to discover, then
  `spideriq campaigns create -q "plumbers" -c US --state "Texas"` (the `--state`
  flag is shorthand for the `mode:regions` + `admin_regions` + `include_postcodes`
  filter above).
- **MCP:** `list_regions(country_code="US")` → pick one → `create_campaign` with the
  same filter. `list_countries` / `list_selectable_units` also discover the unit.

## Gotchas

- **Postcodes are opt-in.** A US `regions`/`all` campaign with no `include_postcodes`
  is cities-only — same as before the ZIP load. You only get the deep ZIP fan-out
  when you set it `true`.
- **One state per campaign.** Multi-state and all-US ZIP runs `422` (volume cap).
  Run several state campaigns in sequence instead.
- **Size first.** `postcode_count × max_results` is the Maps volume — a big state
  with `max_results: 100` is hundreds of thousands of business fetches.

## Verify

- `GET /locations/regions?country_code=US` returns **200** with per-state
  `postcode_count` (a `422` there means the discovery endpoint isn't reachable).
- The campaign's `total_locations` ≈ the chosen state's `postcode_count`.
- Records land under `GET /idap/businesses?campaign_id=<id>`.
