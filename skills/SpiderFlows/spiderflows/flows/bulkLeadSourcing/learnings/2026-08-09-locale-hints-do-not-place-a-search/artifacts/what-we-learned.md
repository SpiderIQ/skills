# `country_code` looks like targeting. It isn't.

**Starting point, not ground truth — verify against current code.**

## The surprise

A `geo` entry has five fields, and four of them sound geographic:

```json
{ "label": "...", "latitude": 0, "longitude": 0, "country_code": "US", "region": "..." }
```

Only two of them place a search.

## What actually steers the provider

```
label            → appended to the query:  "restaurants, Atlanta, Georgia, USA"   ← PLACES IT
latitude/longitude → explicit search centre                                        ← PLACES IT
country_code     → locale hint passed through                                      ← does not
region           → locale hint passed through                                      ← does not
```

The expansion code is literal about it: it builds `"{query}, {suffix}"` from each
geo target's *query suffix* and nothing else. A target with no label and no
coordinates contributes no suffix at all.

## The failure it produces

```json
"geo": [{ "country_code": "US" }]
```

reads as "search the US". It is not. It sends the **bare** query with a US locale
— so you buy a nationwide or arbitrarily-centred result set, pay for it in full,
and get back records that look valid because they *are* valid businesses. They
are just not the ones anyone asked for.

Nothing errors. The run is a clean success with the wrong geography.

## What to do

- **Put the place in `label`.** Write it the way a person would search:
  `"Atlanta, Georgia, USA"`, not `"atlanta"`.
- Use `country_code` **alongside** a label, as the locale hint it is — never
  instead of one.
- Reach for `latitude`/`longitude` when the user wants a radius around a point
  rather than a named place.
- Before submitting, check `estimated_queries` in the 202: if you meant four
  cities and it says 1, your labels never made it in.
