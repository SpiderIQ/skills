# The worker rewrites your query for 26 ambiguous EU cities

**Starting point, not ground truth — verify against current code.**

## The surprise

Submit `"cafes in Hamburg"` and the worker actually searches
`"cafes in Hamburg, Germany"`. It silently appends a country to **26 European
city names that collide with US cities** (Hamburg, Berlin, Munich, Frankfurt,
Paris, Rome, Milan, Vienna, Dublin, Athens, …) so you get the European city, not
the US namesake (there's a Hamburg in New York, an Athens in Georgia, a Paris in
Texas).

This is done by `_enhance_query_with_location()` in the Maps skill, called on
every search.

## When it fires (and when it doesn't)

- **Fires** when the query has no country context: `"cafes in Hamburg"` →
  `"cafes in Hamburg, Germany"`.
- **Does NOT fire** when a country is already present:
  - `"cafes in Hamburg, Germany"` — left as-is.
  - `"cafes in Hamburg DE"` — left as-is (country code detected).

So it's additive and safe: it only disambiguates when you were ambiguous.

## Why it matters for composing a query

- For those 26 cities, you usually **don't need to do anything** — the worker
  handles the disambiguation. `"plumbers in Munich"` lands in Germany.
- If you actually want the US namesake (e.g. Paris, Texas), **say so explicitly**
  in the query — `"bakeries in Paris, Texas"` — so the rewrite doesn't override
  you (it won't touch a query that already names a country/region).
- For cities *not* on the list, or for sub-city precision, be explicit in
  `search_query` anyway — the worker only special-cases these 26 names.

## Connects to

This is the partner of the sibling learning
`2026-05-26-location-goes-in-the-query`: because there's no `country_code` field
on a single Maps job, country targeting for these cities is handled *inside the
query* — partly by you (write the place into `search_query`), partly by the
worker (this auto-append for the 26 known-ambiguous names).
