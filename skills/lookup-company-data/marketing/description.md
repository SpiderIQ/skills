## lookup-company-data

Firmographic enrichment — turn a domain or business name into a structured company profile. 6 tool calls.

### What this skill does

- **`lookup_by_domain`** — single canonical lookup by domain. Returns industry, sub-industry, employee count band, revenue band, founded year, headquarters location, tech stack signals.
- **`lookup_by_name`** — name-based search, returns a ranked list of candidates (multiple companies can share a name).
- **`enrich_business`** — accepts an existing IDAP `business_id`, fills in any missing firmographic fields without overwriting confirmed data.
- **`bulk_lookup`** — batch enrichment for a list of domains/names.
- **`get_lookup_status`** + **`list_lookups`** — async ops, status + history.

### Data sources

SpiderCompanyData aggregates from multiple sources (Crunchbase-class providers, registry data, LinkedIn company pages, on-site signals from `scrape-website-extract-leads`). Confidence scores per field reflect source agreement.

### Typical workflows

- **Pipeline stage 4** — after scraping + verification, agent enriches each business with firmographics so the outreach can be personalized by industry / size.
- **Standalone enrichment** — agent receives a CSV of domains, runs `bulk_lookup`, writes enriched records to IDAP for downstream campaigns.
- **Pre-call research** — agent enriches one specific business right before drafting a personalized outreach email.

### Cost vs precision tradeoffs

`lookup_by_domain` is the cheapest and most precise. `lookup_by_name` is broader but ambiguous — the agent should pick from candidates by additional signal (location, industry hint). For high-volume work, `bulk_lookup` is asynchronous and rate-limited by provider quotas.
