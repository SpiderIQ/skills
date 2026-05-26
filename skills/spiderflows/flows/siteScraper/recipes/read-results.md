# Recipe: read what a site crawl produced

Three read surfaces: the job aggregate (the complete per-site profile), the Flows
run views (single + batch), and IDAP (the normalized contacts a crawl auto-syncs
into your CRM). For one site, the **job aggregate is the right call** — it returns
everything the crawl found in one shot.

## One-shot aggregate → `/jobs/{job_id}/results`

```bash
curl "https://spideriq.ai/api/v1/jobs/{job_id}/results?format=yaml" -H "Authorization: Bearer $SPIDERIQ_PAT"
```

This is the complete site profile: `emails[]`, `phones[]`, `addresses[]`, `logo`,
the 14 flat social fields (`linkedin`, `twitter`, …), `markdown_compendium`,
`company_vitals` / `team_members[]` / `pain_points` / `lead_scoring` (if AI was
enabled), `meta` (landing-page metadata) and `schema_org` (JSON-LD). For a single
flow-facade run, `run_id` **is** the `job_id` — `/jobs/{run_id}/results` works.
See [results-shape.md](results-shape.md) for every field.

## Flows run views (single + batch)

| You want | Call |
|---|---|
| a single run + its sub-results / actor / output | `GET /api/v1/runs/{run_id}` |
| a batch group's roll-up (total / succeeded / failed / pending + per-run status) | `GET /api/v1/run-groups/{run_group_id}` |
| your recent site runs (filter by status) | `GET /api/v1/runs?flow=siteScraper&status=completed` |

`/run-groups/{id}` is the batch dashboard read; `/jobs/{run_id}/results` is still
where the actual crawled data for each member lives.

## Queryable reads → IDAP (auto-synced contacts)

**Every** site crawl's contacts are written into your normalized CRM automatically
— you do **not** need to set `persist.to_normalized`. They become queryable through
IDAP as `businesses`, `contacts`, `emails`, `phones`, and `domains`.

A standalone crawl has **no `campaign_id`**, so scope to the exact site by its
domain with `resolve`:

```bash
# the crawled business + its emails/phones/domains/contacts, by domain
curl "https://spideriq.ai/api/v1/idap/businesses/resolve?domain=example.com&include=emails,phones,domains,contacts&format=yaml" \
  -H "Authorization: Bearer $SPIDERIQ_PAT"
```

Or list across everything you've ever crawled (tenant-wide, paged):

```bash
curl "https://spideriq.ai/api/v1/idap/emails?limit=100&format=yaml" -H "Authorization: Bearer $SPIDERIQ_PAT"
```

| You want | Call |
|---|---|
| the one business you just crawled | `GET /api/v1/idap/businesses/resolve?domain=<domain>&include=emails,phones,domains,contacts` |
| every email across your crawls | `GET /api/v1/idap/emails` |
| every contact (person) found | `GET /api/v1/idap/contacts` |
| the domain records | `GET /api/v1/idap/domains` |

`limit` is 1–500 (default 100); follow the `cursor` until empty. `?fields=...`
projects fewer columns; `?format=yaml` saves 40–76% over JSON. See the
foundation's [reading-results.md](../../../references/reading-results.md) for the
full IDAP parameter set.

## Gotchas

- **For one site, `/jobs/{job_id}/results` is the most complete read.** It carries
  the compendium, AI sections, `meta`, and `schema_org` that don't all have IDAP
  homes. IDAP gives you the normalized *contacts* sliced for paging/filtering, not
  the full crawl artifact.
- **No `campaign_id` on a standalone crawl** — scope IDAP by `domain` (via
  `resolve`) or `search`, not `?campaign_id=`. The tenant-wide list mixes in every
  other site you've crawled.
- **IDAP is contacts-only.** The compendium, `lead_scoring`, `pain_points`, `meta`,
  and `schema_org` live in `/results`, not in the normalized tables.
- **Big compendiums come back as a URL, not inline** (>10 MB → presigned download,
  24h TTL). Re-fetch `/results` for a fresh URL if it expired. See
  [the compendium-storage learning](../learnings/2026-05-26-large-compendium-returns-a-url/artifacts/what-we-learned.md).
- **Emails here are unverified** — extracted off the page, not SMTP-checked.
- **Tenant isolation**: you only ever see your own `client_id`'s records.
- **Don't parse `/status` for data** — it reports *how far along*; `/results` and
  IDAP are the data surfaces.

## Verify

- `GET /jobs/{job_id}/results` returns `crawl_status: success` (or `partial`) and
  `pages_crawled` > 0.
- `GET /idap/businesses/resolve?domain=<domain>` returns the business with the
  emails/phones the crawl found.
- Run [scripts/verify-site-complete.sh](../scripts/verify-site-complete.sh) for a
  deterministic, paste-safe audit of a finished run.
