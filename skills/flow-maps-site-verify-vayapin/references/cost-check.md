# Recipe: size a campaign before you submit

A campaign's `filter` decides how many locations it fans out to — and each
location runs a full Maps → Site → Verify (→ VayaPin) pipeline of up to
`max_results` businesses. Get this wrong and one submit launches thousands of
runs. This is the most expensive mistake in the chain.

## The filter matrix

| `filter.mode` | Locations selected | Required field | Cost |
|---|---|---|---|
| `all` | every location in the country (incl. postcodes) | — | **highest** |
| `cities_only` | every city in the country | — | high |
| `regions` | cities within named admin regions | `admin_regions: [...]` | scoped |
| `population` | locations above/below a population band | `min_population` (and/or `max_population`) | scoped |
| `custom` | a hand-picked list | `location_ids: [...]` | exact |

`all` and `cities_only` over a whole country are the runaway modes. `regions`,
`population`, and `custom` are the safe levers.

## Steps

1. **Default is `all`.** If the user didn't narrow it, assume the widest, most
   expensive expansion and narrow before submitting.

2. **Estimate the location count.** A country-wide `all`/`cities_only` campaign can
   be **thousands** of locations — one `(country: DE, mode: all)` campaign once
   fanned to **1,733 locations** and dispatched 113 worker jobs in 23 seconds.
   Multiply by `max_results` to picture the Maps volume.

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
