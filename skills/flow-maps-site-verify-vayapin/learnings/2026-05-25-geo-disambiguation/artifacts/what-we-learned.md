# Query construction differs single vs campaign — don't double-target

**Starting point, not ground truth — verify against current code.**

## The surprise

The location goes in a *different place* depending on mode, and getting it wrong
silently wastes the run (you don't get an error — you get a worse search).

## Single (`/lead-search`)

The server builds the Maps query from `search_query` + optional `location`:

```python
search_query = request.search_query
if request.location:
    search_query = f"{request.search_query} in {request.location}"
```

So you supply the place **once** — either inside `search_query`
(`"plumbers in Berlin"`) **or** as `location` (`search_query: "plumbers"`,
`location: "Berlin"`). Supplying it in **both** yields `"plumbers in Berlin in
Berlin"` — a degraded query.

## Campaign (`/jobs/spiderMaps/campaigns/submit`)

The query must be **bare** (`"plumbers"`). The locations come from `country_code` +
`filter`, and the campaign enumerator (`country-to-cities`) builds
`"{query} in {city}"` for each location itself. Putting a city in the campaign's
`search_query` double-targets every location — e.g. `"plumbers in Berlin"` run
against a `regions` filter searches "plumbers in Berlin in München", etc.

## Rule of thumb

- Single → location in `search_query` *or* `location`, never both.
- Campaign → `search_query` is the bare term; location is `country_code` + `filter`.
- Country also drives VayaPin locale and Maps `lang`, so set `country_code`
  correctly even when the place is already in the query.
