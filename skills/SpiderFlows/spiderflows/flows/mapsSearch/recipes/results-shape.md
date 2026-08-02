# Reference: the shape of a finished Maps Search record

What a single business looks like after a Maps Search run, so you know what you
can read back. These are the items in `data.businesses[]` from
`GET /jobs/{job_id}/results` (see [read-results.md](read-results.md)).

## Envelope

```yaml
data:
  query: "plumbers in Berlin"     # the search you submitted (place embedded)
  results_count: 18
  businesses: [ <business>, ... ]
  metadata:                       # search settings + post-processing stats
    max_results: 20
    extract_reviews: false
    language: en
    post_processing:
      phone_validation: { total: 18, valid: 15, invalid: 3 }
      image_upload:     { total_images: 18, uploaded: 16, failed: 2 }
```

## A single business (`SpiderMapsBusiness`)

| Field | Notes |
|---|---|
| `name` | Business name. |
| `place_id` | Google's stable place identifier — the key for dedup / downstream enrichment. |
| `address` | Full street address (may be empty if Google doesn't show one). |
| `phone` | Phone as shown on the listing (raw). |
| `phone_e164` | E.164 form (`+49…`) — present when `validate_phones` (default on). |
| `phone_national` | National-format phone — present when `validate_phones`. |
| `phone_type` | `MOBILE` / `FIXED_LINE` / `VOIP` / `TOLL_FREE` / … — present when `validate_phones`. |
| `phone_valid` | Whether the number parsed as valid. |
| `website` | The business's website URL (this is the closest thing to a contact — there are **no emails**). |
| `categories[]` | Google's category labels (e.g. `["Plumber", "Contractor"]`). |
| `rating` | Average star rating (1.0–5.0) — **see the dummy-value caveat below**. |
| `reviews_count` | Number of reviews — **see the dummy-value caveat below**. |
| `coordinates` | `{ latitude, longitude }`. |
| `link` | The Google Maps listing URL. |
| `business_status` | `OPERATIONAL` / `CLOSED_TEMPORARILY` / … |
| `price_range` | `$` / `$$` / `$$$` / `$$$$` when shown. |
| `working_hours` | Opening hours — a structured dict or a summary string. |
| `image_url` | Permanent SpiderMedia URL for the first image — present when `store_images` (default on). |

### `extract_reviews` / `extract_photos` — collected, but not in the typed record

When you set these flags the worker DOES the extra work and writes `reviews: [...]`
(review snippets) and `photos: [...]` (image URLs) into the **raw** job output. But
the typed `/jobs/{job_id}/results` response maps each business through
`SpiderMapsBusiness`, which has **no `reviews` / `photos` field** — so those arrays
are **dropped from the business records you read back.** What survives reliably is:

- `reviews_count` — the number of reviews (always populated).
- `image_url` — the first image (when `store_images`, the default).

So: don't promise the user review *text* or a full photo gallery from the standard
results endpoint. If they need either, flag that the typed read surfaces only the
count + primary image. Detail:
[learnings/2026-05-26-extract-reviews-photos-not-in-typed-results](../learnings/2026-05-26-extract-reviews-photos-not-in-typed-results/artifacts/what-we-learned.md).

## There are no emails here

Maps Search returns the listing's **`website`**, not contact emails — Google Maps
doesn't expose them. Email discovery + SMTP verification is the SpiderSite +
SpiderVerify stages of the **lead chain** (`searchLeads`). If the user expects
emails, you're on the wrong flow.

## Gotchas

- **`rating: 4.0` and `reviews_count: 1024` can be placeholders, not real data.**
  When Google detects automation it serves a reduced "compact" JSON format whose
  `rating` defaults to `4.0` and `reviews_count` to `1024`. The worker's DOM
  layer fills the real values when it can, but if you see *exactly* `4.0` /
  `1024` across many businesses, treat them as suspect rather than truth.
  (See [learnings/2026-05-26-compact-format-dummy-values](../learnings/2026-05-26-compact-format-dummy-values/artifacts/what-we-learned.md).)
- **Missing `website` / `phone` / `address` ≠ extraction failure.** Plenty of
  real businesses simply don't list all three on Google Maps. Check
  `metadata` (and `data.results_count`) before calling a run incomplete.
- **`coordinates` / `working_hours` shapes vary.** `working_hours` may be a dict
  (per-day) or a single summary string — handle both. `coordinates` is
  `{latitude, longitude}` when present.
- **`fuzziq_unique` may appear but is meaningless** — FuzzIQ was removed from the
  pipeline; don't build logic on it.

## Reading it back

There's one read path: `GET /jobs/{job_id}/results` (see
[read-results.md](read-results.md)). Standalone Maps results are **not** in IDAP
— that's the campaign lead-chain surface.
