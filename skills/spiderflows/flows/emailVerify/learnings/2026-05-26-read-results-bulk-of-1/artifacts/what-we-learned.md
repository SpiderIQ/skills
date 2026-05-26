# Single-email verify is bulk-of-1 — the verdict is in `results[0]`

**Starting point, not ground truth — verify against current code.**

## The surprise

You submit `{"payload": {"email": "jane@acme.com"}}`, the job completes, and you
read `GET /jobs/{job_id}/results`. You look for `status` / `score` at the top of
the result — and they're empty. The natural conclusion ("the verify produced
nothing") is wrong.

## What's actually happening

emailVerify emits **one shape** regardless of how many emails you sent:

```yaml
total: 1
summary: { valid: 1, invalid: 0, risky: 0, unknown: 0, fuzziq_skipped: 0 }
billable_count: 1
results:
  - email: jane@acme.com
    status: valid
    score: 95
    ...
metadata: { ... }
```

A single email is a **bulk job of one** — its verdict lives in `results[0]`. The
worker used to also copy the single-email fields to the top level, but they were
always `None` even for single jobs (the worker wraps single → bulk internally), so
they were removed. Reading them today gets you nothing.

## What to do

- **Single:** read `results[0]`.
- **Batch:** iterate `results[]`.
- **Counts:** read `summary` — and trust it over recounting `results[]`, because
  `summary.fuzziq_skipped` covers addresses that were deduped and aren't present
  in `results[]` as billable rows.
- **What you paid for:** `billable_count` (which is below `total` when dedup ran).

## Rule of thumb

There is no "single result" object — there is always a list. Read `results[0]`
for one email; never read `status`/`score` at the envelope's top level.
