---
name: spiderflows
description: >
  Run SpiderIQ flows — server-side pipelines that chain scraping and enrichment
  workers and land results you read back through IDAP. Trigger on: "find local
  businesses in <city>", "scrape leads", "build a verified lead list", "get
  dentists/plumbers/restaurants in <place>", "local SEO", "leadSearch", "find
  business emails", "google maps scrape with contact details", "run a SpiderIQ
  pipeline", "run a campaign". A flow runs once (single) or across many locations
  (campaign); you submit, poll or stream progress, then read results. This one
  skill covers the client surfaces (HTTP / CLI / MCP), the Bearer PAT, response
  formats, live progress, reading results, and the cost gate every flow shares —
  plus each flow's payload and recipes. Today it implements the lead /
  local-business pipeline (Maps → Site → Verify → VayaPin), sold as both
  leadSearch and localSeo; more flows are added here as recipes.
---

# SpiderFlows

A **flow** is a SpiderIQ pipeline: you submit one request, SpiderIQ runs a chain
of workers server-side, and the results land in your account where you read them
back through IDAP. You never run the workers yourself — you drive flows through
one surface (HTTP API, CLI, or MCP), all on `https://spideriq.ai/api/v1` with one
Bearer token.

This is **one skill** for all SpiderIQ flows. Shared mechanics (auth, formats,
progress, reading results, the cost gate) live here once; each flow adds its
payload + recipes. The flow implemented today:

```
flow:maps-site-verify-vayapin   (marketed as leadSearch AND localSeo — one chain)
SpiderMaps        SpiderSite            SpiderVerify        VayaPin
find businesses → crawl each website → verify the emails → publish a map pin
on Google Maps    (emails, phones,      (deliverability,    (optional; see the
                   socials, team)        score)              HARD-GATE)
```

`leadSearch` (verified-leads output) and `localSeo` (published-pin output) are the
**same** chain — the only difference is whether the vayapin stage publishes.

## Approach

- **Single location** — one city, one search. Fastest; use
  [references/run-single.md](references/run-single.md). Always safe on cost.
- **Campaign** — the same search across many locations (a country/region/population
  band). Use [references/run-campaign.md](references/run-campaign.md), and respect
  the cost gate first ([references/cost-check.md](references/cost-check.md)).
- **Manage / read** — stop, resume, retry, delete, and read results out
  through IDAP. See [references/manage-campaign.md](references/manage-campaign.md)
  and [references/read-results.md](references/read-results.md).

<HARD-GATE name="cost-budget">
Before submitting a **campaign**, know how many locations it will fan out to. A
`filter.mode` of `"all"` or `"cities_only"` over a whole country expands to *every*
city — one `(country: DE)` campaign once fanned to **1,733 locations** and burned
113 worker jobs in 23 seconds. If you are about to submit a country-wide campaign
without a `population` or `regions` narrowing, STOP: narrow the filter, or submit
and immediately check `total_locations` in the response and `stopCampaign` if it is
larger than intended. A single-location run is always safe — this gate is campaigns
only. ([references/cost-check.md](references/cost-check.md))
</HARD-GATE>

<HARD-GATE name="vayapin-default-on">
The vayapin stage publishes a **real, public profile on cs.vayapin.com** for every
business with a website — and those pages are **permanent: deleting the campaign
does NOT remove them.** Its default is path-dependent (on for `/lead-search` with an
omitted `workflow`; whatever you send on a campaign), so **never rely on the default
— always set `workflow.vayapin.enabled` explicitly.** If the user asked for a *lead
list* (data to export / outreach) and did NOT ask to publish anything, set
`{"workflow": {"vayapin": {"enabled": false}}}`. Only set it `true` when the user
explicitly wants published map profiles. When in doubt, ask — you cannot undo a
published pin. ([references/vayapin-export.md](references/vayapin-export.md))
</HARD-GATE>

## Rules (Non-Negotiable)

**Auth:** every call carries `Authorization: Bearer <client_id>:<api_key>:<api_secret>` (a PAT). CLI/MCP load it from `~/.spideriq/credentials.json`; for raw HTTP, never echo the secret into logs or chat.

**Never tight-loop:** after submit, poll status no faster than every 3–5 seconds, or use the SSE stream. Workers take seconds-to-minutes per location.

**Query construction differs by mode.** Single: put the location *inside* the query (`"plumbers in Berlin"`) or pass `location` — not both. Campaign: the query is *bare* (`"plumbers"`); location comes from `country_code` + `filter`. A city in both double-targets and wastes the run.

**Stages are opt-in past Maps.** `workflow.spidersite.enabled`, `workflow.spiderverify.enabled`, `workflow.vayapin.enabled` gate each stage. SpiderVerify and VayaPin both require SpiderSite (422 otherwise). Maps always runs.

**Read results through IDAP, by `campaign_id`.** `GET /api/v1/idap/businesses?campaign_id=<id>&include=emails,phones,domains,pins`. Don't parse progress endpoints for data. (`pins` is read via `include`, not as a standalone type.)

**Stop before you delete.** `deleteCampaign` refuses (409) while a campaign has active jobs. Stop it, let in-flight jobs settle, then delete.

## Decision tree — pick a recipe

| The user wants to… | Read |
|---|---|
| understand the surfaces / auth / `?format=yaml` before the first call | [references/surfaces-and-auth.md](references/surfaces-and-auth.md) |
| run one city / one search (lead list or local SEO) | [references/run-single.md](references/run-single.md) |
| run a search across many locations (country / region / population band) | [references/run-campaign.md](references/run-campaign.md) |
| check how big a campaign will be BEFORE submitting | [references/cost-check.md](references/cost-check.md) |
| stop / resume / retry / delete a campaign | [references/manage-campaign.md](references/manage-campaign.md) |
| read the businesses, emails, phones, and pins a run produced | [references/read-results.md](references/read-results.md) |
| understand poll-vs-SSE progress and realistic timing | [references/run-modes-and-progress.md](references/run-modes-and-progress.md) |

## Per-stage settings (quick map — full detail in the reference)

| Stage | Key settings | Reference |
|---|---|---|
| Maps | `search_query`, `country_code`, `max_results` (1–500), `lang` | [references/per-stage-settings.md](references/per-stage-settings.md) |
| Site | `mode` (contacts / compendium / leads / full), `max_pages`, `extract_team`, CHAMP `product_description`+`icp_description` | [references/per-stage-settings.md](references/per-stage-settings.md) |
| Verify | `check_gravatar`, `check_dnsbl`, `max_emails_per_business` | [references/per-stage-settings.md](references/per-stage-settings.md) |
| VayaPin | `enabled` (path-dependent default — see the HARD-GATE) | [references/vayapin-export.md](references/vayapin-export.md) |

## Methods (native tool calls — opvsHUB & marketplace)

This skill ships as typed tool calls generated from `client/schema.yaml`:

| Method | Does | Recipe |
|---|---|---|
| `searchLeads` | run one location (single) | [references/run-single.md](references/run-single.md) |
| `createCampaign` | run across many locations | [references/run-campaign.md](references/run-campaign.md) |
| `listCampaigns` / `getCampaignStatus` / `getJobStatus` | list + poll progress | [references/run-modes-and-progress.md](references/run-modes-and-progress.md) |
| `stopCampaign` / `continueCampaign` / `updateCampaign` | halt / resume / edit config | [references/manage-campaign.md](references/manage-campaign.md) |
| `retryLocation` / `retryFailedLocations` | recover failures | [references/manage-campaign.md](references/manage-campaign.md) |
| `deleteCampaign` | delete (409 if active; pins persist) | [references/manage-campaign.md](references/manage-campaign.md) |
| `getJobResults` / `getCampaignResults` / `readResources` | read results (IDAP) | [references/read-results.md](references/read-results.md) |

The envelope contract (`guidance:` per method — `use` / `next` / `warn` /
`telemetry_signal_default`, plus skill-level `intent_aliases`) lives in
[client/schema.yaml](client/schema.yaml).

## References (loaded on demand)

**Shared (read first in a session):**
- **[references/surfaces-and-auth.md](references/surfaces-and-auth.md)** — surfaces, Bearer PAT, `?format=yaml|md`.
- **[references/run-modes-and-progress.md](references/run-modes-and-progress.md)** — single vs campaign, poll vs SSE, timing.
- **[references/reading-results.md](references/reading-results.md)** — the IDAP read surface (resource types, `include`, paging).

**flow:maps-site-verify-vayapin:**
- **[references/run-single.md](references/run-single.md)** · **[references/run-campaign.md](references/run-campaign.md)** · **[references/cost-check.md](references/cost-check.md)** — submit.
- **[references/manage-campaign.md](references/manage-campaign.md)** — stop / resume / retry / delete.
- **[references/read-results.md](references/read-results.md)** — read this chain's results.
- **[references/per-stage-settings.md](references/per-stage-settings.md)** — every setting per stage. **Read before composing a non-trivial `workflow` block.**
- **[references/vayapin-export.md](references/vayapin-export.md)** — what vayapin publishes, the opt-out, verifying pins.
- **[references/campaign-results-shape.md](references/campaign-results-shape.md)** — the fields a finished business record carries.

## See also

- `learnings/` — the cost-runaway, vayapin-default-on, and geo-disambiguation lessons (starting points, not ground truth — verify against current code).
- `scripts/verify-pipeline-complete.sh` — audits a finished run against its expected stages.
