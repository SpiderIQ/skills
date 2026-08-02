# Country-wide campaign filters fan out to thousands of locations

**Starting point, not ground truth — verify against current code.**

## What happened

A campaign was submitted with `country_code: "DE"` and no deliberate `filter`.
`CampaignFilterConfig.mode` defaults to `"all"`, which selects *every* location in
the country — cities and postcodes. The campaign expanded to **1,733 locations**
and dispatched **113 worker jobs in 23 seconds** before anyone noticed. Each
location runs a full Maps → Site → Verify pipeline of up to `max_results`
businesses, so the true cost is `locations × max_results` pipelines.

## Why it bites

- The default is the **widest** mode (`all`). Omitting `filter` doesn't mean "small"
  — it means "everything".
- `max_results` is **per location**. `100 × 1,733` is ~173k Maps results worth of work.
- A single `POST` launches the whole fan-out; there's no incremental confirmation step.

## What to do

1. Estimate the location count *before* submitting — see `references/cost-check.md`.
2. Narrow with `mode: "regions"` (+ `admin_regions`), `mode: "population"`
   (+ `min_population`), or `mode: "custom"` (+ `location_ids`).
3. If you must run wide, read `total_locations` off the `201` response and `stop`
   the campaign immediately if it's larger than intended — a stopped campaign halts
   before most locations dispatch.

A **single** `/lead-search` run is always safe; this is a campaign-only trap.
