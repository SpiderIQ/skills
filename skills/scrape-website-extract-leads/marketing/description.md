## scrape-website-extract-leads

The "scrape any website, get clean lead data back" skill. 4 tool calls — submit, status, results, list. Powered by SpiderSite worker (~163 instances across the VPS fleet).

### What this skill does

- **`submit_site_scrape`** — accepts a URL + extraction config (max pages, depth, contact-only mode). Returns `job_id`.
- **`get_site_results`** — returns extracted emails (with confidence scores), phone numbers, social profiles (LinkedIn, Twitter, Facebook, Instagram), and full page markdown for downstream LLM analysis.
- **`get_site_status`** — page-count progress, ETA.
- **`list_site_jobs`** — paginated history.

### Extraction pipeline

Inside SpiderSite each job goes through:

1. **Crawl** — Playwright + SpiderBrowser pool, depth-limited BFS up to `max_pages`
2. **Extract** — regex pass for emails/phones (with anti-obfuscation), LLM pass for context (`spideriq/extraction` task alias on SpiderGate V2 — typically an 8B model)
3. **Score** — confidence per email (page placement, surrounding text, mailto: presence, role-account heuristic)
4. **Persist** — extracted entities written to IDAP (`businesses`, `domains`, `emails`, `contacts` tables) for cross-campaign deduplication

### Typical workflows

- **Pipeline stage 2** — after `scrape-google-maps` returns 90 listings, agent calls `submit_site_scrape` for each business's website to enrich with emails/phones.
- **One-off enrichment** — agent receives a known business URL, scrapes for contact info before drafting outreach.
- **Lead validation** — agent re-scrapes a previously-seen business to detect changes (new contacts added, old emails removed).

### Costs

Provider browser time + SpiderGate V2 LLM tokens for the extraction pass.
