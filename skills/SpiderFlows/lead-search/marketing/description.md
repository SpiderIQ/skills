## lead-search

The "I just want enriched leads, fast" skill. 6 tool calls covering the full Maps → Site → Verify → VayaPin pipeline for a single location, without the campaign-management overhead of `run-enrichment-pipeline`.

### What this skill does

- **`submit_lead_search`** — accepts: `search_query` (e.g. "plumbers"), `country_code`, `location` (city). Optional `workflow` config to disable stages. Returns `job_id`.
- **`get_lead_search_results`** — final enriched list: businesses with phone/email/website/social/firmographics/verified-deliverability.
- **`get_lead_search_status`** — pipeline progress, per-stage timing.
- **`list_lead_searches`** — history.
- **`cancel_lead_search`** — abort.
- **`continue_lead_search`** — resume a paused search.

### Why this exists separately

`run-enrichment-pipeline` is the right answer for multi-location campaigns. But >90% of practical lead-gen work is "I need ~50 leads in one city, and I need them now." For that, the pipeline-management overhead is a tax. `lead-search` is the fast-path: one call, one result, all stages auto-orchestrated.

### Pipeline stages (default config)

1. **SpiderMaps** — search the location, get business listings
2. **SpiderSite** — for each business website, scrape contacts
3. **SpiderVerify** — drop bouncing emails
4. **VayaPin** — add phone numbers for businesses missing one

Each stage can be disabled via the `workflow` config:
```json
{ "spidersite": { "enabled": true }, "spiderverify": { "enabled": false } }
```

Disabling stages = faster + cheaper but less enrichment depth.

### Typical workflows

- **Demo / trial usage** — first call an agent makes after install. Validates the pipeline works end-to-end without setting up a campaign.
- **Just-in-time leads** — agent receives "find me 30 dentists in Munich for tomorrow's outreach", calls `submit_lead_search`, polls until done, drafts outreach.
- **Pipeline calibration** — agent runs a small `lead-search` to see typical result density + timing before committing to a multi-city campaign.

### Cost

Sum of per-stage costs (Maps + Site + Verify + VayaPin). Brands typically configure per-day quotas to bound runaway agent loops.
