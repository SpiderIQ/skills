## run-enrichment-pipeline

Full pipeline orchestration. 12 tool calls — the high-level "submit a campaign and let the platform handle the fan-out" surface.

### What this skill does

Where `scrape-google-maps` + `scrape-website-extract-leads` + `verify-email-deliverability` are the individual stages, `run-enrichment-pipeline` runs them all together as a WindMill workflow with proper sequencing, retries, and aggregation.

- **`create_campaign`** — accepts: search_query, list of locations, country, workflow config (`{spidersite: {enabled: true}, spiderverify: {enabled: true}}`). Returns `campaign_id`. Maps stages can be disabled — e.g. Maps-only for fast counts, or Maps+Site without verification.
- **`get_campaign_status`** — overall campaign progress with per-stage breakdown (Maps: 80% complete, Site: 30%, Verify: 0%).
- **`get_campaign_results`** — paginated final output: enriched businesses with all contact info aggregated.
- **`list_campaigns`** — all campaigns for the brand.
- **`stop_campaign`** / **`continue_campaign`** — pause + resume. State persists in WindMill, so a campaign can be paused mid-run and resumed days later.
- **`update_campaign`** — change workflow config mid-run (e.g. disable verification stage if cost is overrunning).
- **Plus 5 more diagnostic / cleanup methods**

### Architecture

WindMill orchestrates 470 worker slots across 11 VPS. Each stage submits to the appropriate Postgres `job_queue` (SpiderSite, SpiderVerify) or RabbitMQ queue (legacy services). Aggregation happens via callbacks — each worker, on completion, posts a partial result back to WindMill which writes it to the campaign's aggregate output.

### Typical workflows

- **Multi-city campaign** — agent submits "plumbers" across 50 cities in Germany, full pipeline. WindMill fans out, results stream back over hours-to-days.
- **Iterative refinement** — agent starts with Maps-only (fast, cheap), reviews counts, decides to enable Site+Verify on the most promising cities.
- **Long-running re-enrichment** — agent re-runs an old campaign with updated workflow config to refresh stale data.

### When to use this vs `lead-search`

Use `lead-search` for **one location, fast results**. Use `run-enrichment-pipeline` for **many locations, willing to wait**. They're not interchangeable — pipeline is heavier infrastructure with checkpoint/resume.
