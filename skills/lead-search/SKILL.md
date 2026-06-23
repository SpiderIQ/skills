---
name: lead-search
version: "1.0.0"
description: >
  Single-location lead generation — find businesses on Google Maps, crawl their websites, verify emails, and create VayaPin profiles. Full pipeline in one call.

category: data-collection
requires_auth: true
requires_brand: true
triggers:
  - find leads
  - lead search
  - search businesses
  - lead generation
client: lead-search
client_version: "1.0.0"
metadata:
  openclaw:
    primaryEnv: OPVS_PAT
---

# lead-search #data_collection

search and discover leads across enrichment boards — filter by industry, location, CHAMP score, data completeness

/#find-people-extract-linkedin-profile → specific person lookup by name
/#scrape-google-maps → finding businesses by geography
/#company-intel → deep company research with full pipeline

## Chain
searchLeads → getJobResults → lead-enrichment_moveTask (qualify matches)

## Pitfalls
- Vague queries return too many results — always include industry + location
- CHAMP scores below 40 are low confidence — verify before outreach

## Methods

- `searchLeads(search_query, country_code?, location?, max_results?, lang?, workflow?, test?)` — Run the full lead generation pipeline for a search query in a location. Maps → Site → Verify → VayaPin. Returns job_id to poll for results.
- `getJobStatus(job_id)` — Check status of a lead search job.
- `getJobResults(job_id)` — Get results of a completed lead search.
