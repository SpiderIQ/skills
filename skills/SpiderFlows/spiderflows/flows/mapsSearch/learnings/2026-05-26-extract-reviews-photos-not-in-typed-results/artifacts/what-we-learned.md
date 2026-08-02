# `extract_reviews` / `extract_photos` don't survive to the typed results

**Starting point, not ground truth — verify against current code.**

## The surprise

You set `extract_reviews: true` (or `extract_photos: true`) expecting review text
(or a photo gallery) in the results. The worker *does* the work — it writes
`reviews: [...]` and `photos: [...]` into its raw output. But when you read
`GET /jobs/{job_id}/results`, those arrays **aren't there.**

## Why

The results endpoint runs every business through the `SpiderMapsBusiness` Pydantic
model before returning it. That model:

- has **no `reviews` field and no `photos` field**, and
- does **not** set `extra="allow"`, so unknown keys are dropped, and
- the transform that builds it (`transform_spidermaps_data`) never even passes
  `reviews` / `photos` into the constructor.

So the rich arrays exist in the raw worker result but are filtered out of the
typed business records you actually read back.

## What you reliably get

- **`reviews_count`** — the number of reviews (always populated, regardless of the
  flag).
- **`image_url`** — the first image (when `store_images` is on, the default).

## How to handle it

- **Don't promise the user review *text* or a full photo gallery** from the
  standard `/jobs/{id}/results` read. You can give them the review *count* and the
  primary image.
- If a use case genuinely needs the snippets/gallery, flag it: the data is
  collected at the worker but not surfaced by the typed endpoint, so it's a
  product gap to escalate — not something a different payload field will fix.
- Practically: leave `extract_reviews` / `extract_photos` off for normal runs —
  they add real time (the worker visits more of each listing) for data you can't
  read back through this endpoint anyway.

## Rule of thumb

`reviews_count` + `image_url` = yes. `reviews[]` text + `photos[]` gallery = not
through the typed results. Set expectations accordingly.
