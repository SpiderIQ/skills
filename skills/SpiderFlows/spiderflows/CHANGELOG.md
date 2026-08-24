# Changelog — @spideriq/spiderflows

Format: keep-a-changelog. Marketing-only changes (assets under `marketing:` in the
manifest) do NOT trigger a manifest bump.

Backfilled at 0.10.0 — this package had no changelog before, so entries earlier than
0.10.0 are not recorded here. `manifest.yaml` `version:` is the authority for what has
been published; marketplace versions are immutable.

## [Unreleased]

## [0.11.0] — 2026-08-23 — internal sources: enrich the leads a tenant ALREADY owns

Feature release. Adds `flows/internalSources/` — the recipe set for `provider: "internal"`,
which aims the same Site → Verify → VayaPin chain at leads already in the tenant's own
corpus instead of buying more. Owner ruling 2026-08-16 retired the planned in-dashboard
natural-language box: **the agent is the NL layer**, so the skill teaches an agent to read
the field catalogue and author a validated filter AST itself.

Numbered `0.11.0` rather than `0.10.0` (its original in-flight number) because `0.10.0`
was taken by the Sortlist release while this slice was in review, and marketplace versions
are immutable.

### Added

- **`flows/internalSources/`** — 4 recipes (`internal-vs-buying.md` · `build-a-filter.md` ·
  `eligible-not-matched.md` · `run-internal.md`), 3 learnings, and
  `scripts/verify-internal-complete.sh`.
- **6 methods on `client/schema.yaml`** covering both internal `source_kind`s —
  `unenriched_run` (re-run a past campaign that was never enriched) and `corpus_query`
  (a filter AST over `norm_cli_*`): catalogue → count → selection → submit.
- **Router triggers** in `SKILL.md` for the possessive tell — *"our leads"*, *"re-run the
  X campaign"*, *"we never verified those emails"*. Buying a second copy of leads the
  tenant already owns is the failure this flow exists to prevent, and per-purchase dedup
  does not catch it.

### Fixed

- **`verify-internal-complete.sh` asked for `?format=json` and would have died on its first
  request.** The `format` param on `/jobs/{id}/status` is validated against `^(yaml|md)$`, so
  naming JSON is a `422 SCHEMA_VALIDATION_FAILED` — which `curl -fsS` reports as a bare failure
  that reads like a bad PAT or an outage. JSON is the default; you reach it by omitting the param.
  This script was authored **before** `0.10.1`/`0.10.2` swept the same bug out of the other eight
  bundled scripts, so it shipped the defect those releases had just retired. The CI guard that
  globs all 16 shipped scripts is what caught it.

### Changed

- `manifest.yaml` `description` recompressed to **994/1024** so the internal-sources
  capability is named alongside Sortlist without dropping any other flow. The cap is
  enforced server-side (`422 string_too_long`), so the union had to be compressed rather
  than concatenated.

### Notes

- ⚠️ **Free at the source is not a free run.** `internal` is `source_is_free=True`, so every
  money field reads `0`/`null` while the run still spends `eligible_leads × stages`
  downstream. Branch on `source_is_free`, never on `!has_cost` — an unpriced *provider*
  (`outscraper`) is indistinguishable from a free source on every money field.
- ⚠️ **Quote `eligible_leads`, never `matched_leads`.** *"Select 5,000, enrich 200"* is the
  ordinary reading on a mature corpus, and `eligible` is what the record ceiling, the cost
  and the runtime are all decided by. It is scoped to the stage set, so a count carried
  between stage sets is simply wrong.

## [0.10.2] — 2026-08-22 — the other seven verify scripts, and a guard that covers scripts nobody has written yet

Bug-fix release. `0.10.1` fixed `?format=json` in **one** of the eight bundled
`verify-*.sh` scripts and shipped the other seven with it — twice, since `0.10.0`
had it in all eight. This finishes the sweep. No API behaviour changes.

### Fixed

- 🔴 **Six shipped verify scripts died on their FIRST request and verified nothing.**
  `format` on `/jobs/{id}/status` and `/jobs/{id}/results` is validated against
  `^(yaml|md)$`. JSON is the default and the only way to ask for it is to **not
  ask** — naming it is a `422 SCHEMA_VALIDATION_FAILED`, which `curl -fsS` renders
  as a bare `ERR: request failed` that reads like auth or an outage. The param is
  now omitted, and the reason is pinned beside each fetch helper, because *"it was
  `?format=json` and someone tidied it back in"* is the obvious regression.

  **Every one of the six was verified against a real terminal job of its own type**
  — a control run before the fix (`ERR: request failed`, exit 2) and a real verdict
  after:

  | Script | Job type | After the fix |
  |---|---|---|
  | `siteScraper/…/verify-site-complete.sh` | `spiderSite` | 10 pages, 2 emails / 2 phones — exit 0 |
  | `mapsSearch/…/verify-maps-complete.sh` | `spiderMaps` | 1 business, 1 with website — exit 0 |
  | `emailVerify/…/verify-emails-complete.sh` | `spiderVerify` | 4 checked · 2 valid / 1 invalid / 1 risky — exit 0 |
  | `linkedinProfiles/…/verify-people-complete.sh` | `spiderPeople` | mode=company, 5 employees — exit 0 |
  | `companyRegistry/…/verify-companydata-complete.sh` | `spiderCompanyData` | mode=search, 3 records — exit 0 |
  | `perplexity-…-people/…/verify-intel-complete.sh` | `companyIntel` | 1 company, discovery + LinkedIn + people — exit 0 |

### Changed

- **`maps-site-verify-vayapin/…/verify-pipeline-complete.sh` — hardened, not fixed.**
  `0.10.1` listed this script among the seven broken ones. It was **not broken**.
  Its two routes — `…/campaigns/{id}/workflow-results` and `/idap/businesses` — do
  not *declare* a `format` param, so FastAPI silently discarded it and both
  answered `200` with the param present. Run unmodified against a real completed
  campaign it produced a correct verdict (22 businesses, 18 emails found, exit 0).

  The param is removed anyway: it is one `Query(...)` declaration away from
  becoming the same 422 that killed its six siblings, and its silence is what let
  the bug survive here unnoticed. **Nothing this script reported was ever wrong**,
  so no result produced with an earlier version needs re-checking — which is not
  true of the six above, every one of which reported nothing at all.

- **The same seven scripts ship a SECOND time, and were broken there too.**
  `packages/skills/dist/spiderflows/` is the copy that goes out as
  `@spideriq/skills` on Verdaccio (`files: ["lib","dist"]`), installed by
  `spideriq skills add`. It is hand-maintained committed content, **not** build
  output — `tsup` writes `lib/`, never `dist/` — so nothing regenerates it and
  nothing checked it. All seven scripts there carried the same `?format=json` and
  are fixed identically here.

  ⚠️ **That tree is otherwise 6 weeks stale and is NOT resynced by this release.**
  Its last content commit is `909599aa7` (2026-07-09) against the source's
  `d115a1677` (2026-08-21), and it is missing two whole flows — `bulkLeadSourcing`
  (so SDS-23's fix never reached it either) and `commerce-funnels`. Only the
  `?format=json` defect is corrected; the staleness needs its own card.

### Guard

- **The regression assertion now sweeps the package, not one file.**
  `tests/fixtures/verify-bulk/run-verify-bulk-tests.sh` case 12 already failed the
  build if the *bulk* script regained `?format=json` — and it was green through
  both releases that shipped seven siblings carrying it, because it read only the
  one file somebody had already fixed. It now globs every
  `flows/*/scripts/verify-*.sh` in **both trees that ship these scripts** (see
  below), prints a **denominator** (`swept 15 scripts`), and fails if the glob
  matches nothing. Because it globs, it covers scripts that do not exist yet —
  proven by running it against the not-yet-merged `internalSources` script from
  open PR #3573, which carries the bug: the sweep went red without anyone
  extending a list. Three RED controls were run and all three fired — a regression
  in a sibling script, a regression in the second tree, and an unseen new script.

## [0.10.1] — 2026-08-21 — reading a bulk run takes TWO steps, and the verify script said otherwise

Bug-fix release. `0.10.0` shipped two files that told agents to read a bulk run's
leads off the **parent** job. Card `SDS-20` then changed what a bulk parent
returns, and the parent is a **funnel summary** that has never carried, and will
never carry, a `businesses` array. Nothing here changes the API — this corrects
what the skill says about it.

### Fixed

- 🔴 **`scripts/verify-bulk-complete.sh` printed a FALSE FAILURE on healthy runs.**
  It hunted `data.businesses` on the parent, found none, and printed
  `RESULT: FAIL — status is completed but the run produced no leads`. It now reads
  the parent for the funnel and follows `data.children.job_ids` for the leads, and
  it separates four outcomes the old script collapsed into one FAIL:

  | Outcome | Verdict |
  |---|---|
  | the screen kept 0 of N, with `drop_reasons` | `COMPLETE` — an **answer** (exit 0) |
  | leads present, contact data present | `PASS` (exit 0) |
  | leads present, no contacts, but `sites_completed > 0` | `PASS (no contacts found)` (exit 0) |
  | leads present, no contacts, no enrichment stage enabled | `COMPLETE (sourcing only)` (exit 0) |
  | leads present, site stage enabled but never ran | `SUSPECT` (exit 1) |
  | the payload is not a bulk parent at all | `CANNOT AUDIT` (exit 2) — a wrong **address**, not an empty run |

- 🔴 **Every URL in that script carried `?format=json`, which is a 422.** The
  `format` param is validated against `^(yaml|md)$`; JSON is the default, reached
  by omitting the param. The script therefore died on its **first** request with a
  generic `request failed` that reads as an auth or outage problem. Measured live
  2026-08-21. ⚠️ **The other 7 bundled `verify-*.sh` scripts in this package have
  the identical bug and are NOT fixed here** — see the note at the end.

- **`recipes/read-results.md` sent agents to the wrong door.** Step 2 said to read
  the per-lead results "exactly as for a campaign" against the parent `job_id`. It
  now teaches the two-step read: parent → `screening` / `cost` / `children`, then
  `children.job_ids[]` → the leads.

- **The "envelope is identical to a campaign's" table was attached to the wrong
  noun.** The 10/10, 4/4 and 24/24 figures are correct — of a bulk **child**, not
  the parent. Re-attached, and re-verified live against production children
  `1d169a58` and `97c44c7b`. Same correction applied in `SKILL.md`,
  `recipes/bulk-vs-campaign.md` and `recipes/run-bulk.md`, which all repeated it.

- **`recipes/run-bulk.md` told you to invoke the verify script with the wrong id**
  (`<bulk_job_id>` instead of the parent `<job_id>`). The script now says so
  explicitly when it happens, instead of failing with a bare "request failed".

- **`coordinates` keys were wrong.** The gotcha named `{ lat, lng }`; the shipped
  and measured shape is `{ latitude, longitude }`. Reading the short names yields
  `undefined` and looks like missing geo data — the same failure the gotcha exists
  to prevent.

### Changed

- **`kept: 0` is documented as an ANSWER, not an error.** A run that delivered 20
  records and kept 0 because `drop_reasons: {too_few_reviews: 20}` is the caller's
  own screening floor working correctly. `screening` **absent entirely** is what a
  broken run looks like. Reading zero as breakage recreates the defect this
  release fixes.

- **Zero contact data is no longer read as a false green by default.**
  `workflow_progress.sites_completed` on the campaign aggregate reports whether the
  site stage RAN, independently of whether it FOUND anything — so "SpiderSite ran
  and the sites had nothing" is now distinguished from "SpiderSite never ran".
  Its siblings on that response (`total_businesses`, `total_emails_found`,
  `locations`) read `0` / `[]` for a bulk campaign and must not be used.

- **The 100-id cap on `children.job_ids` is documented**, along with
  `job_ids_truncated` and the `workflow_results_endpoint` to use past it.

### Known issues — stated, not fixed

- **IDAP-by-campaign is unverified for bulk runs.** A live check found zero rows in
  the tenant's normalized corpus carrying a bulk run's `source_job_id` or a
  `bulk_%` `source_campaign_id`, while a bare `/idap/businesses` for the same
  tenant returned rows. Cause not established. `read-results.md` now marks that
  path unverified instead of presenting it as the better option.

- **`GET /jobs/spiderMaps/campaigns/{id}/jobs` returns `total: N` with `jobs: []`
  for bulk campaigns.** Documented as a gotcha; `children.job_ids` is inlined to
  route around it.

- **`?format=json` 422s in the other 7 bundled verify scripts**
  (`siteScraper`, `mapsSearch`, `emailVerify`, `linkedinProfiles`,
  `companyRegistry`, `perplexity-site-companydata-people`,
  `maps-site-verify-vayapin`). All 8 carried it; only the bulk one is in this
  release's scope, and the other 7 were not re-verified end-to-end here. They need
  their own card. — *Resolved in 0.10.2 (card SDS-27). Six of those seven were
  genuinely dead on arrival; the seventh (`maps-site-verify-vayapin`) was listed
  here in error and worked throughout, because neither of its routes declares the
  `format` param.*


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
