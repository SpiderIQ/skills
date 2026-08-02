## scrape-google-maps

The starting point for most lead-gen campaigns. 5 tool calls covering search submission, status polling, results retrieval, and review extraction.

### What this skill does

- **`submit_maps_search`** — submits a Google Maps query (e.g. "plumbers in Berlin") + country/language. Returns a `job_id`.
- **`get_maps_results`** — fetches business listings: name, address, phone, website, rating, review count, hours, categories, place_id.
- **`get_maps_reviews`** — paginated review extraction per business. Useful for sentiment analysis or competitive research.
- **`list_maps_jobs`** — paginated list of past Maps jobs for the active brand.
- **`cancel_maps_job`** — abort an in-flight scrape.

### Worker model

SpiderMaps runs through SpiderBrowser (Camoufox-backed anti-detect Firefox pool, 48 profiles across 11 VPS). Submitted jobs land on a Postgres `job_queue`, workers claim with `SKIP LOCKED` for bounded latency under contention.

### Typical workflows

- **Initial discovery** — agent submits a wide search, gets ~90 listings, hands off to `scrape-website-extract-leads` for the next stage.
- **Competitive review mining** — agent pulls reviews for a competitor, runs sentiment analysis, surfaces themes.
- **Coverage check** — agent runs a small search, looks at result density, decides whether to expand or pivot the campaign.

### Costs

Google Maps API + provider browser time. Brands have per-skill quotas configurable in the dashboard. Agents that exceed get a soft warn first, then a hard block.
