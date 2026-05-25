---
name: spiderflows
description: >
  Run SpiderIQ flows — server-side pipelines that chain scraping and enrichment
  workers and land results you read back through IDAP. Trigger on: "run a
  SpiderIQ pipeline", "scrape leads", "find local businesses in <city>", "build
  a lead list", "run a campaign", "enrich companies", or any multi-step
  data-collection job on SpiderIQ. A flow runs once (single) or across many
  locations (campaign); you submit, poll or stream progress, then read results.
  This is the foundation skill — it covers the client surfaces (HTTP / CLI /
  MCP), the Bearer PAT, response formats, live progress, reading results, and
  the cost gate every flow shares. For a specific pipeline, load its per-flow
  skill: lead and local-business discovery (Maps → Site → Verify → VayaPin) is
  flow-maps-site-verify-vayapin.
---

# SpiderFlows

A **flow** is a SpiderIQ pipeline: you submit one request, SpiderIQ runs a chain
of workers server-side, and the results land in your account where you read them
back through IDAP. You never run the workers yourself — you drive flows through
one of four surfaces (HTTP API, CLI, MCP, or a per-flow skill), all on
`https://spideriq.ai/api/v1` with one Bearer token.

This skill is the shared foundation: surfaces, auth, formats, progress, reading
results, and the cost gate. For the payload, per-stage settings, and recipes of
a specific pipeline, load that pipeline's per-flow skill (decision tree below).

## Approach

1. **Pick the flow chain** for the job. Each chain has its own skill with the
   exact payload, per-stage settings, and worked recipes.
2. **Load that per-flow skill** and follow its run recipe.
3. **Submit → watch → read.** Submit returns a `job_id` (single run) or a
   `campaign_id` (campaign). Watch with polling or the live SSE stream. Read
   results through IDAP.

<HARD-GATE name="cost-budget">
Before submitting a **campaign**, know how many locations it will fan out to.
A `filter.mode` of `"all"` or `"cities_only"` over a whole country expands to
*every* city — one `(country: DE)` campaign once fanned to **1,733 locations**
and burned 113 worker jobs in 23 seconds. If you are about to submit a
country-wide campaign without a `population` or `regions` narrowing, STOP:
narrow the filter, or submit and immediately check `total_locations` in the
create response and `stop_campaign` if it is larger than intended. A
single-location run (one city, via `/lead-search` or single mode) is always
safe — this gate is about campaigns.
</HARD-GATE>

## Rules (Non-Negotiable)

**Auth:** every call carries `Authorization: Bearer <client_id>:<api_key>:<api_secret>` (a PAT). The CLI and MCP load it for you from `~/.spideriq/credentials.json`; for raw HTTP, never echo the secret into logs or chat.

**Never tight-loop:** after submit, poll status no faster than every 3–5 seconds, or subscribe to the SSE stream. Workers take seconds-to-minutes per location — a spin loop just burns tokens and rate limit.

**Read results through IDAP:** results are read with `GET /api/v1/idap/<type>` — valid `<type>`s are `businesses`, `contacts`, `emails`, `phones`, `domains` (plus `company_registry`, `linkedin_profiles`, `staff`, `bookings`, `media`) — filtered by `campaign_id`. Published VayaPin pins are read as a relation **on** businesses (`?include=pins`), not as a standalone type. The status endpoints report *progress*; IDAP is the queryable, paginated, flaggable read surface for the *data*.

**Ask for YAML:** add `?format=yaml` to GET calls (or set `SPIDERIQ_FORMAT=yaml`). On large result sets that is 40–76% fewer tokens than JSON.

**Name the chain, not the marketing label:** refer to a flow by its worker chain (`flow:maps-site-verify-vayapin`), not a marketing name. The same chain is sometimes sold under two names (for example "leadSearch" and "localSeo") — they are the *same* pipeline, differing only by a default flag. Naming the chain keeps you from treating one capability as two.

## Decision tree — pick a flow

| The user wants to… | Load skill |
|---|---|
| find local businesses, scrape leads, or build a verified lead list (Google Maps → crawl the site → verify emails → optional map pins) | **`flow-maps-site-verify-vayapin`** |
| _(as the suite grows)_ deep company research — Perplexity → site → company registry → people | `flow-perplexity-site-companydata-people` |
| _(as the suite grows)_ a single worker only — just Maps search, just a site crawl, just email verification | the matching per-service skill |

If you only need **one** worker (scrape a single URL, verify a list of emails),
you don't need a flow — submit a single job for that service. Flows are for
**chains** of workers run as one pipeline.

## References (loaded on demand)

- **[references/surfaces-and-auth.md](references/surfaces-and-auth.md)** — the four client surfaces (HTTP / CLI / MCP / skill), the Bearer PAT, and `?format=yaml|md`. **Always read** before your first call in a session.
- **[references/reading-results.md](references/reading-results.md)** — IDAP read surface plus the campaign results endpoint; how to go from a finished run to its businesses, emails, and pins. **Always read** before reading results.
- **[references/run-modes-and-progress.md](references/run-modes-and-progress.md)** — single vs campaign, polling vs the live SSE stream, and realistic timing so you set the right expectation with the user.

## See also

- The per-flow skill for your chain (decision tree above) — that is where the payload, per-stage settings, and recipes (its `references/`) live.
- Each per-flow skill ships deterministic `scripts/` you can run and paste — e.g. `flow-maps-site-verify-vayapin/scripts/verify-pipeline-complete.sh` audits a finished run against its expected stages.
