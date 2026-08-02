# Identical submissions are cached for 24 hours

**Starting point, not ground truth — verify against current code.**

## The surprise

Submit the exact same Maps Search payload twice within 24 hours and the second
call does **not** scrape again — it returns the **same `job_id`** with
`from_cache: true` in the submit response. You get the first run's results back
instantly.

## Why it's there

It's deliberate deduplication: it makes retries idempotent and saves a redundant
browser session if two callers ask for the same thing. For most uses it's a free
win.

## When it bites

- **The user wants *fresh* data** ("re-run that, the listings changed"). A plain
  re-submit gives them the cached run, not a new scrape — they'll think nothing
  updated.
- **Batch with duplicate queries.** If your list has `"plumbers in Berlin"` twice
  (or you re-run a batch within 24h), the duplicates collapse to one cached
  `job_id` — you won't get N fresh runs.

## How to handle it

- **Always read `from_cache`** in the `201` submit response. If it's `true` and
  the user wanted fresh data, tell them, and:
- **Force a fresh run** by changing the payload — vary the query, or set
  `"test": true` (which also routes to the test queue, dev only). Any change that
  makes the payload non-identical defeats the cache.
- **De-dupe your batch list** before looping, so you don't waste calls expecting
  distinct results from identical queries.

## Rule of thumb

Cache = good for idempotent retries, bad when freshness matters. Check
`from_cache`; if the user said "refresh", make the payload different.
