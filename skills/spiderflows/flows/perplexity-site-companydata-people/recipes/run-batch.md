# Recipe: research many companies (batch)

The same five-stage chain run across a **list** of companies in one request — up
to **50** per batch. Use this for KYC enrichment, list enrichment, or building a
dossier for every name on a target list ("enrich these 40 vendors", "run KYC on
this account list", "build briefs for my ABM targets").

This is *batch*, not *campaign*: you hand it an explicit list of companies, each
with its own hints. (Company Intel has no `campaign` mode — there's no
"every company in a country" fan-out. If the user wants every *local business*
in a place, that's the [maps-site-verify-vayapin](../../maps-site-verify-vayapin/recipes/run-campaign.md)
chain instead.)

## Steps

1. **Build the list.** Each entry is a full `CompanyIntelRequest` — so each
   company carries its own `company_name` + optional `city`/`country_code`/`domain`/`linkedin_url`
   hints. Mixed countries are fine.

2. **Set shared defaults once** at the top level (`profile_mode`, `max_employees`,
   `config`) — they apply to every company. A per-company `config` overrides for
   that one entry.

3. **Submit** `POST /api/v1/company-intel/batch`:

   ```bash
   curl -X POST "https://spideriq.ai/api/v1/company-intel/batch" \
     -H "Authorization: Bearer $SPIDERIQ_PAT" \
     -H "Content-Type: application/json" \
     -d '{
       "profile_mode": "short",
       "config": { "spiderpeople": { "enabled": true, "max_employees": 10 } },
       "companies": [
         { "company_name": "Tesco",  "country_code": "GB" },
         { "company_name": "Pleo",   "country_code": "DK", "domain": "pleo.io" },
         { "company_name": "Stripe", "country_code": "US", "linkedin_url": "https://www.linkedin.com/company/stripe" }
       ]
     }'
   ```

   Response (`201`): `{ "job_id": "...", "type": "batch", "companies_count": 3, "flow": "company_intel_batch", "status": "processing" }`.
   One `job_id` covers the whole batch.

4. **Watch** — poll `GET /jobs/{job_id}/status` (≥3–5s) or the SSE stream. A batch
   runs many companies × five stages each, so size your expectation accordingly —
   tens of companies is many minutes. The stream emits one `job.queued` for the
   batch; per-company progress is read from the aggregate results.

5. **Read** the aggregate: `GET /jobs/{job_id}/results?format=yaml` returns a
   per-company breakdown. For queryable / paged reads across all the companies'
   records, use IDAP — see [read-results.md](read-results.md).

## Key fields (`CompanyIntelBatchRequest`)

| Field | Default | Notes |
|---|---|---|
| `companies` | — (required) | 1–50 entries, each a full single-company request (own hints) |
| `profile_mode` | `short` | shared employee detail level for all companies |
| `max_employees` | `20` | shared per-company employee cap |
| `config` | all stages on | shared per-stage config (per-company `config` overrides) |
| `test` | `false` | routes to the test queue (dev only) |

## Gotchas

- **Hard cap of 50 companies per batch.** A list of 200 vendors is four batches.
  Submitting >50 is a `422`.
- **Hints are per-company.** Put each company's `domain`/`linkedin_url` on *its*
  entry, not at the top level — top-level only carries shared `profile_mode` /
  `max_employees` / `config`.
- **`country_code` matters per company** — it constrains that company's registry
  lookup and (for `GB`) auto-enables financials. Set it where you know it.
- **Cost scales with the list × `profile_mode`.** A 50-company batch with
  `profile_mode: full_email` is a lot of LinkedIn + verification work. Default to
  `short` for large lists; reserve `full`/`full_email` for short, high-value lists.
- **Partial results per company are normal.** One company can miss its registry
  filing or LinkedIn page while the rest succeed — the batch still completes. Read
  each company's per-stage status in the aggregate.

## Verify

- `companies_count` in the response matches the list length you sent.
- `flow` is `company_intel_batch`.
- `GET /jobs/{job_id}/results` returns one record per company once `status` is
  `completed`.
