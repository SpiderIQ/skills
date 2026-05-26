# Re-running the same payload within 24h is free — use it, and know its trap

**Starting point, not ground truth — verify against current code.**

## The surprise

The job-submit layer hashes your `payload`. If an **identical** payload was
submitted (by you or your tenant) in the last **24 hours**, it returns that prior
job instead of running a new one — and the submit response says **`from_cache:
true`**. No second charge, instant result.

For paid people calls this matters both ways:

## The good half — free re-reads

- Need the same profile / search / roster again today? Re-submit the same payload —
  you get the cached result for **$0**, instantly. No need to store the `job_id`
  just to re-read; the dedup hands you the same run.
- Cost of a *fresh* run, for reference: profile ~$0.003, search ~$0.01, company
  **$4 / $8 / $12 per 1,000** employees (`short` / `full` / `full_email`).

## The trap — "fresher data" needs a changed payload

- Re-submitting the **same** payload expecting newer data just returns the cache.
  LinkedIn changed since this morning? The dedup doesn't know that. To force a
  genuinely new (billed) scrape, **change a field**: bump `max_employees`, switch
  `profile_mode`, reword the `search_query`, etc.
- Don't loop-submit the same job "to retry" — within 24h you'll keep getting the
  same cached result (which is the point, but won't fix a bad first run). For a
  transient *failure*, see
  [transient-vs-terminal-failures](../2026-05-26-transient-vs-terminal-failures/).

## Rule of thumb

- Same data again today → just re-submit (free, `from_cache: true`).
- New data → change the payload.
- Budget cost on **fresh** runs only; cached hits are free.
