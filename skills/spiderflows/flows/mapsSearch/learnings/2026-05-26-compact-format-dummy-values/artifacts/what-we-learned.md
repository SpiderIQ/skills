# `rating: 4.0` and `reviews_count: 1024` might be placeholders

**Starting point, not ground truth — verify against current code.**

## The surprise

Google Maps doesn't always serve the full data blob. When it detects automation
(TLS fingerprinting, rate pressure), it returns a reduced **compact** format that
carries little more than `name` + `place_id`. In that format, two fields come
back as fixed placeholders:

- `rating` → `4.0`
- `reviews_count` → `1024`

These are **not the business's real numbers.** A whole result set showing the
exact pair `rating: 4.0, reviews_count: 1024` is the signature of compact-format
responses, not 18 genuinely-4.0-star businesses with exactly 1024 reviews each.

## What the worker does about it

The scraper runs a **DOM-extraction layer** as a safety net: it reads the real
values off the rendered page and merges them in to replace `None`/empty/dummy
JSON values. So most of the time you get real ratings even under compact format.
But it can't always recover everything, so the placeholders sometimes survive
into results.

## The rule

- If `rating` / `reviews_count` matter to the user (ranking, filtering "≥ 4
  stars"), **sanity-check for the `4.0` / `1024` signature** before trusting
  them. Repeated identical pairs across many listings → suspect, not truth.
- `name`, `place_id`, `address`, `website`, `phone`, `coordinates` are reliable;
  `rating` / `reviews_count` are the two to watch.

## A related, separate gotcha — missing ≠ failed

Not every business lists a website, phone, or address on Google Maps. A business
record with a blank `website` is usually a genuine data gap, **not** an
extraction bug. Check `data.results_count` and the run's `metadata` before
telling the user a run was incomplete — and use
[`scripts/verify-maps-complete.sh`](../../../scripts/verify-maps-complete.sh) to see
field coverage at a glance (it also flags the `4.0`/`1024` placeholder count).
