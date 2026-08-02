---
name: company-intel
version: "1.0.0"
description: >
  Company intelligence research — full pipeline: Perplexity discovery, website crawl, company registry lookup, email verification, and people/LinkedIn extraction. Single or batch (up to 50).

category: data-collection
requires_auth: true
requires_brand: true
triggers:
  - company research
  - company intel
  - research company
  - company data
client: company-intel
client_version: "1.0.0"
metadata:
  openclaw:
    primaryEnv: OPVS_PAT
---

# company-intel #data_collection

deep company research — full pipeline: Perplexity discovery, website crawl, registry lookup, email verify, LinkedIn extraction

/#lookup-company-data → basic company registration/VAT data only
/#scrape-google-maps → local business discovery by geography
/#scrape-website-extract-leads → website scraping without company context

## Chain
researchCompany → getJobStatus (poll 10s) → getJobResults
researchBatch (up to 50) → getJobStatus → getJobResults

## Limits
$batch:max 50 companies per batch job

## Pitfalls
- If you know the domain, pass it — skips Perplexity discovery step (faster)
- If you know the LinkedIn URL, pass it — skips LinkedIn search step
- Single company research is faster for urgent requests — use researchBatch for bulk

## Case $t:2026-04
UK fintech companies: Batch(15 companies)→Discovery→Site crawl→Companies House→Verify→LinkedIn→12 complete profiles. 12min.

## Methods

- `researchCompany(company_name, city?, country_code?, domain?, linkedin_url?, profile_mode?, max_employees?, config?, test?)` — Research a single company through the full intelligence pipeline. Returns job_id to poll for results via GET /jobs/{job_id}/results. → getJobStatus (poll every 10s)
- `researchBatch(companies, profile_mode?, max_employees?, config?, test?)` — Research multiple companies in batch (max 50). Same pipeline, processes all companies. Returns job_id to poll. → getJobStatus (poll every 10s) [WARN: max 50 companies per batch]
- `getJobStatus(job_id)` — Check status of a company intel job.
- `getJobResults(job_id)` — Get results of a completed company intel job.
