# Recipe: read what a linkedinProfiles run produced

Two paths: the per-job aggregate (authoritative + immediate) or queryable IDAP
reads (normalized, populated asynchronously). For this flow **the job aggregate is
the primary read** — a people job has no campaign and its full output lands on
`/jobs/{job_id}/results`.

## Primary → `/jobs/{job_id}/results`

```bash
curl "https://spideriq.ai/api/v1/jobs/{job_id}/results?format=yaml" -H "Authorization: Bearer $SPIDERIQ_PAT"
```

**Read the top-level `status` first**, then branch on `mode`:

| Mode | `status: success` gives you | empty/edge |
|---|---|---|
| `profile` | a `profile` (flat fields + experience/education/languages) | `status: unavailable` = private profile (terminal) |
| `search` | `query`, `google_query`, `results_count`, `profiles[]` (shallow) | `results_count: 0` = no first-page hits (valid) |
| `company` | `company_slug`, `employees_count`, `employees[]` | `employees_count: 0` = no public roster / wrong slug (valid) |

See [results-shape.md](results-shape.md) for every field per mode.

### Two flags worth checking

- **`from_cache: true`** (on the submit response) — the platform returned a job with
  an identical payload submitted in the last 24h; the results are the cached run's,
  and you were **not** charged again. Expected and good — not stale data to "fix".
- **`revoked_by_dispatcher: true`** (in the payload) — a long-running scrape was
  reaped by the dispatcher before it finished; treat the result as incomplete and
  resubmit. Rare; only on jobs that ran past their SLA.

## Queryable reads → IDAP, by type

The people a run produced also normalize into IDAP as their own resource types —
useful when you want to page, project fields, or query across **all** the people
you've collected (not just one job). Normalization runs through the CRM sync
**after** the job completes, so there's a short lag before these populate.

| You want | Call |
|---|---|
| the LinkedIn profile/company records | `GET /api/v1/idap/linkedin_profiles?format=yaml` |
| the people as contacts | `GET /api/v1/idap/contacts?format=yaml` |

```bash
curl "https://spideriq.ai/api/v1/idap/linkedin_profiles?format=yaml" -H "Authorization: Bearer $SPIDERIQ_PAT"
curl "https://spideriq.ai/api/v1/idap/contacts?format=yaml"          -H "Authorization: Bearer $SPIDERIQ_PAT"
```

### Paging & projection

`limit` is 1–500 (default 100); follow the `cursor` until it's empty.
`?fields=full_name,headline,location` projects fewer columns; `?format=yaml` saves
40–76% over JSON. Full IDAP parameter set: the foundation's
[reading-results.md](../../../references/reading-results.md).

## Gotchas

- **The job aggregate is immediate; IDAP is eventually-consistent.** `/jobs/{id}/results`
  is ready the moment the job completes; the IDAP rows are written by the CRM sync
  afterward. Query the aggregate first; fall back to IDAP for cross-job/paged reads
  once it has caught up. See
  [results-land-in-job-then-idap](../learnings/2026-05-26-results-job-then-idap/).
- **Standalone people jobs have no `campaign_id`.** Don't filter these IDAP reads by
  `campaign_id` — they're tenant-scoped. (When SpiderPeople runs *inside* the
  company-intel chain, read those records via that flow's
  [read-results.md](../../perplexity-site-companydata-people/recipes/read-results.md).)
- **Don't parse progress endpoints for data.** `GET /jobs/{id}/status` tells you
  *how far along*; `/results` and IDAP are the data surfaces.
- **Tenant isolation.** You only ever see your own `client_id`'s records.
- **Empty section ≠ failure.** Private profile, no-hits search, or an empty roster
  all complete successfully — see
  [empty-is-not-failure](../learnings/2026-05-26-empty-is-not-failure/).

## Verify

- `GET /jobs/{job_id}/results` returns the mode-matched payload with `status:
  success` once `/status` is `completed`.
- `GET /idap/linkedin_profiles` returns rows for the people once the CRM sync has
  run (allow a short lag after completion).
