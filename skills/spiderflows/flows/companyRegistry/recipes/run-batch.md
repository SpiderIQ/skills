# Recipe: look up many companies in a registry (batch)

Several companies' registry filings in one go — KYC checks on a vendor list,
validating a list of VAT numbers, resolving registration numbers for an account
list ("check these 30 suppliers in Companies House", "validate all these VAT
numbers", "get the filing for each name on this list").

## There is no native batch endpoint — batch = a loop of single jobs

The standalone `spiderCompanyData` worker takes **one** lookup per submit
(`POST /jobs/spiderCompanyData/submit` accepts a single `payload`). It has **no**
`/batch` route. "Batch" here means *you* submit N single jobs and collect the N
`job_id`s — there is no single job that fans out across a list.

```bash
# submit one job per company, keep the job_ids
for ID in 00445790 00048839 02627406; do
  curl -s -X POST "https://spideriq.ai/api/v1/jobs/spiderCompanyData/submit" \
    -H "Authorization: Bearer $SPIDERIQ_PAT" -H "Content-Type: application/json" \
    -d "{\"payload\": {\"mode\": \"lookup\", \"identifier\": \"$ID\", \"country\": \"GB\"}}" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["job_id"])'
done
```

Then poll each `job_id` and read each result (see
[read-results.md](read-results.md)). Or skip the per-job juggling entirely and
read the normalized rows together from IDAP — every completed **search/lookup**
lands in the same `company_registry` table (vat does **not** normalize — read those
per-job):

```bash
curl "https://spideriq.ai/api/v1/idap/company_registry?format=yaml&limit=100" \
  -H "Authorization: Bearer $SPIDERIQ_PAT"
```

## When you actually want enriched batch → use the company-intel chain

If the user wants *more than the filing* for each company — domain, site crawl,
LinkedIn team, verified emails — don't loop registry lookups. The company-intel
chain has a real batch endpoint (`POST /company-intel/batch`, up to 50 companies,
one `job_id` for the whole list) and the registry is just one of its five
stages. See
[../../perplexity-site-companydata-people/recipes/run-batch.md](../../perplexity-site-companydata-people/recipes/run-batch.md).

| The user wants… | Use |
|---|---|
| just the registry filing for many companies | this recipe — loop `spiderCompanyData` single jobs |
| filing **+** domain / LinkedIn / verified emails for many companies | company-intel `researchCompaniesBatch` (`/company-intel/batch`, ≤50) |

## Steps

1. **Build the list of payloads.** Each is a full single-job `payload` — so each
   company carries its own `mode` + the fields that mode needs (a `lookup` needs
   `identifier`+`country`; a `vat` needs `vat_number`). Mixed modes and countries
   in one batch are fine; they're independent jobs.
2. **Submit one job per entry** and keep each `job_id` (and which company it was
   for — the response doesn't echo your input).
3. **Pace the submits.** Don't fire hundreds at once — you share the 100 req/min
   client rate limit and the registries throttle. A small sleep between submits
   for a long list is polite and avoids `429`s.
4. **Watch** each job (`GET /jobs/{job_id}/status`, ≥3–5s) or just wait and read
   the aggregate from IDAP once they've all settled.
5. **Read** — either per-job (`/jobs/{job_id}/results`) or all together via
   `GET /idap/company_registry` (paged; follow the `cursor`). See
   [read-results.md](read-results.md).

## Gotchas

- **No batch `job_id`.** Each company is its own job — there's no single id that
  covers the list. Track the `job_id → company` mapping yourself as you submit.
- **The response doesn't carry your input.** Record which company each `job_id`
  belongs to at submit time, or rely on the normalized IDAP rows
  (`name` / `registration_number`) to re-associate after the fact.
- **Per-company coverage is UK/US for records, EU only for vat.** A
  `search`/`lookup` resolves UK + US only; a `lookup` with any other country returns
  `success:false "Unsupported country"`. EU companies are reachable only via `vat`
  (validation). One entry coming back empty/`success:false` doesn't fail the others.
  Empty ≠ failure (see
  [learnings/2026-05-26-empty-result-is-normal/](../learnings/2026-05-26-empty-result-is-normal/artifacts/what-we-learned.md)).
- **Check each job's `data.success`, not just HTTP 200.** A not-found / unsupported
  lookup is still `status: completed` (HTTP 200) with `data.success:false` — read it
  per job (see
  [learnings/2026-05-26-success-flag-not-http-status/](../learnings/2026-05-26-success-flag-not-http-status/artifacts/what-we-learned.md)).
- **UK financials × a long list adds up.** `include_financials` is ~$0.05 *each*
  and slow (OCR), UK-only (ignored on US). Only set it for the UK companies that
  actually need accounts. Everything else (search, plain lookup, vat) is free.

## Verify

- You have one `job_id` per company you submitted.
- Each `GET /jobs/{job_id}/status` reaches `completed`.
- `GET /idap/company_registry` returns the resolved companies' rows (some entries
  may be legitimately absent — out-of-coverage companies produce no row).
