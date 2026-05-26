# Location goes IN the query — not in a separate field

**Starting point, not ground truth — verify against current code.**

## The surprise

The Maps Search flow definition (`app/flows/mapsSearch.yaml`) lists `location`
and `country_code` as input fields. It's natural to write:

```json
{ "payload": { "search_query": "plumbers", "location": "Berlin", "country_code": "DE" } }
```

…and expect it to search plumbers in Berlin, Germany. It won't. The single Maps
worker **never reads `location` or `country_code`.**

## What actually happens

- The single-job payload model (`SpiderMapsJobPayload`) doesn't define
  `location` or `country_code` at all — extra fields are dropped at validation,
  so they never reach the worker.
- The worker (`googlemaps/search.py`) reads `search_query` / `url`,
  `max_results`, `lang`, `country` (note: `country`, not `country_code`),
  `extract_reviews`, `extract_photos`.
- `country_code` and `filter` are **campaign-only** concepts (the lead chain's
  multi-location fan-out), not single-job fields.

So `location: "Berlin"` is silently ignored, and you get plumbers from wherever
Google defaults the bare term — usually not what the user wanted.

## The rule

**Put the place inside `search_query`:**

```json
{ "payload": { "search_query": "plumbers in Berlin", "max_results": 20 } }
```

- One string carries both the *what* and the *where*.
- The worker also auto-disambiguates 26 ambiguous European city names by
  appending the country (`"cafes in Hamburg"` → Germany, not the US namesake) —
  see the sibling learning `2026-05-26-geo-disambiguation-eu-cities`.

## Why it matters

This is the single most common way to get wrong-location Maps results: trusting
the flow's marketing `input_schema` instead of the worker contract. The schema
is aspirational; the worker is what runs. When you compose a Maps Search, embed
the location in the query and ignore the `location` / `country_code` fields the
schema advertises.

## Note for the facade batch path

The Flows facade (`POST /flows/mapsSearch/run`) validates against that same
aspirational schema, so it will *accept* `location` / `country_code` / a
`max_results` up to 500 without error — and then the worker ignores them anyway.
Keep the place in `search_query` and `max_results ≤ 100` regardless of which
surface you use.
