# Changelog — @spideriq/spiderflows

Format: keep-a-changelog. Marketing-only changes (assets under `marketing:` in the
manifest) do NOT trigger a manifest bump.

Backfilled at 0.10.0 — this package had no changelog before, so entries earlier than
0.10.0 are not recorded here. `manifest.yaml` `version:` is the authority for what has
been published; marketplace versions are immutable.

## [Unreleased]

## [0.10.0] — 2026-08-19 — bulk lead sourcing learns the Sortlist agency directory

### Added

- **`sortlist` documented as a client-selectable bulk source.** It occupies the same
  slot as `outscraper` / `apify` on `POST /bulk-lead-sourcing/submit`, with the same
  buy order, fan-out and result envelope — but you pick from its published catalogue
  instead of typing a search term, and nothing is bought to start the run. New recipe
  [`flows/bulkLeadSourcing/recipes/sortlist-agencies.md`](flows/bulkLeadSourcing/recipes/sortlist-agencies.md).

  Selection vocabulary: **109 services** (bare slugs) + **26 industries** (`i/` prefix)
  in the one `queries` array — 135 options between them — across **21 country** slugs
  that carry their own ISO code. Country is the smallest unit; there is no city or
  radius targeting.

- **Learning: an off-catalogue slug is accepted at submit, then kills the run.**
  Membership is validated in the worker, not in `prepare_submission`, so a bad slug
  returns an ordinary `202` with a `job_id` and fails ~5s later. Nothing is contacted
  and nothing is spent — but the `202` gives no warning, so poll the job status once
  before reporting a Sortlist run as started.
  ([`learnings/2026-08-19-an-off-catalogue-slug-is-accepted-then-kills-the-run`](flows/bulkLeadSourcing/learnings/2026-08-19-an-off-catalogue-slug-is-accepted-then-kills-the-run/artifacts/what-we-learned.md))

### Changed

- **`source_kind` gained `sortlist_agency`**, and its eligible downstream stages are
  stated on the field: `spidersite` · `spiderverify` · `social_media_enrichment` ·
  `smartlead`. **VayaPin is a 422**, and the schema now carries the reason —
  **republication**, because VayaPin mints permanent public profile pages with no
  un-publish path. It is explicitly *not* the LinkedIn source's reason (a missing
  address); a Sortlist agency has one, so a reader who assumes the analogy concludes
  the exclusion is an oversight and removes it.

- **The `bulk-is-one-irreversible-purchase` hard gate no longer says every bulk run
  buys records.** A free source purchases nothing to start but still commits the
  caller to `N records x enabled stages` downstream, so the gate now applies to both
  and says why. `guidance.warn` and the `provider` field say the same thing:
  **`estimated_cost_usd: null` never means free** — an unpriced *paid* provider
  returns it too.

- **The `provider` field enumerates what is actually registered**, adding `internal`
  (re-enrich leads the tenant already owns) alongside the existing note that `csv` /
  `json` need a dashboard-only multipart upload first.

- Frontmatter triggers now route agency-shaped requests ("find SEO agencies",
  "marketing agencies in <country>", "branding studios") to the bulk flow.
