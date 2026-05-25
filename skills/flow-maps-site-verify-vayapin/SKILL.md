---
name: flow-maps-site-verify-vayapin
description: >
  Run SpiderIQ's lead and local-business pipeline: search Google Maps, crawl
  each business's website, verify the emails found, and (optionally) publish a
  VayaPin map profile. Trigger on: "find local businesses in <city>", "scrape
  leads", "build a verified lead list", "get dentists/plumbers/restaurants in
  <place>", "local SEO", "leadSearch", "find business emails", "google maps
  scrape with contact details". This is the chain marketed as both leadSearch
  and localSeo — they are the SAME pipeline; the only difference is whether map
  pins get published (the vayapin stage). Runs as a single location or a
  multi-location campaign. For the shared surfaces, auth, formats, progress, and
  the campaign cost gate, see the spiderflows foundation skill.
---

# flow-maps-site-verify-vayapin

The lead / local-business pipeline. One request fans out across four workers:

```
SpiderMaps        SpiderSite            SpiderVerify        VayaPin
find businesses → crawl each website → verify the emails → publish a map pin
on Google Maps    (emails, phones,      (deliverability,    (optional; see the
                   socials, team)        score)              HARD-GATE)
```

It is sold under two marketing names — **leadSearch** (verified-leads output)
and **localSeo** (published-pin output) — but it is one chain. The difference is
a single flag: `vayapin.enabled`. Name the chain, not the label.

Read the **spiderflows** foundation skill first for auth, `?format=yaml`,
progress (poll vs SSE), reading results via IDAP, and the campaign cost gate.
This skill adds what is specific to *this* chain: the payload, the per-stage
settings, and the recipes.

## Approach

- **Single location** — one city, one search. Fastest path; use
  [references/run-single.md](references/run-single.md). Always safe on cost.
- **Campaign** — the same search across many locations (a country, a region, a
  population band). Use [references/run-campaign.md](references/run-campaign.md),
  and respect the foundation's cost gate first
  ([references/cost-check.md](references/cost-check.md)).
- **Manage / read** — stop, resume, retry failed locations, delete, and read the
  results out through IDAP. See
  [references/manage-campaign.md](references/manage-campaign.md) and
  [references/read-results.md](references/read-results.md).

<HARD-GATE name="vayapin-default-on">
The vayapin stage publishes a **real, public profile on cs.vayapin.com** for every
business with a website — and those pages are **permanent: deleting the campaign
does NOT remove them.** Its default is path-dependent (on for `/lead-search` with
an omitted `workflow`; whatever you send on a campaign), so **never rely on the
default — always set `workflow.vayapin.enabled` explicitly.** If the user asked
for a *lead list* (data to export / outreach) and did NOT ask to publish anything,
set `{"workflow": {"vayapin": {"enabled": false}}}`. Only set it `true` when the
user explicitly wants published map profiles. When in doubt, ask — you cannot undo
a published pin.
</HARD-GATE>

## Rules (Non-Negotiable)

**Query construction differs by mode.** Single mode: put the location *inside* the
query — `search_query: "plumbers in Berlin"` — or pass `location` (not both).
Campaign mode: the query is *bare* (`"plumbers"`) and the location comes from
`country_code` + `filter`; SpiderIQ builds `"{query} in {location}"` for each
location itself. A city in **both** double-targets and wastes the run.

**Stages are opt-in past Maps.** `workflow.spidersite.enabled`,
`workflow.spiderverify.enabled`, and `workflow.vayapin.enabled` gate each stage.
SpiderVerify requires SpiderSite and VayaPin requires SpiderSite (both 422 if
violated). Maps always runs.

**Read results through IDAP, by `campaign_id`.** After a run completes,
`GET /api/v1/idap/businesses?campaign_id=<id>&include=emails,phones,domains,pins`.
Don't parse the progress endpoints for data. (`pins` is read via `include`, not as
a standalone type.)

**Stop before you delete.** `DELETE /campaigns/{id}` refuses (409) while a campaign
has active jobs. Stop it, let in-flight jobs settle, then delete.

## Decision tree — pick a reference

| The user wants to… | Read |
|---|---|
| run one city / one search (lead list or local SEO) | [references/run-single.md](references/run-single.md) |
| run a search across many locations (a country / region / population band) | [references/run-campaign.md](references/run-campaign.md) |
| check how big a campaign will be BEFORE submitting | [references/cost-check.md](references/cost-check.md) |
| stop / resume / retry failed locations / delete a campaign | [references/manage-campaign.md](references/manage-campaign.md) |
| read the businesses, emails, phones, and pins a run produced | [references/read-results.md](references/read-results.md) |

## Per-stage settings (quick map — full detail in the reference)

| Stage | Key settings | Reference |
|---|---|---|
| Maps | `search_query`, `country_code`, `max_results` (1–500), `lang` | [references/per-stage-settings.md](references/per-stage-settings.md) |
| Site | `mode` (contacts / compendium / leads / full), `max_pages`, `extract_team`, CHAMP `product_description`+`icp_description` | [references/per-stage-settings.md](references/per-stage-settings.md) |
| Verify | `check_gravatar`, `check_dnsbl`, `max_emails_per_business` | [references/per-stage-settings.md](references/per-stage-settings.md) |
| VayaPin | `enabled` (path-dependent default — see the HARD-GATE) | [references/vayapin-export.md](references/vayapin-export.md) |

## References (loaded on demand)

- **[references/run-single.md](references/run-single.md)** — submit one location via `/lead-search`.
- **[references/run-campaign.md](references/run-campaign.md)** — fan out across many locations.
- **[references/cost-check.md](references/cost-check.md)** — size a campaign before submitting. **Read before any country-wide campaign.**
- **[references/manage-campaign.md](references/manage-campaign.md)** — stop / resume / retry / delete.
- **[references/read-results.md](references/read-results.md)** — read businesses, emails, phones, pins via IDAP.
- **[references/per-stage-settings.md](references/per-stage-settings.md)** — every setting per stage, defaults, and cost. **Read before composing a non-trivial `workflow` block.**
- **[references/vayapin-export.md](references/vayapin-export.md)** — what vayapin publishes, the path-dependent default, the opt-out, verifying pins.
- **[references/campaign-results-shape.md](references/campaign-results-shape.md)** — the fields a finished business record carries (Maps + Site + Verify).

## Methods (native tool calls — opvsHUB & marketplace)

On opvsHUB and the marketplace this skill ships as typed tool calls generated
from `client/schema.yaml`. Same surface as the HTTP recipes above:

| Method | Does | Recipe |
|---|---|---|
| `searchLeads` | run one location (single) | [references/run-single.md](references/run-single.md) |
| `createCampaign` | run across many locations | [references/run-campaign.md](references/run-campaign.md) |
| `listCampaigns` / `getCampaignStatus` / `getJobStatus` | list + poll progress | [references/run-campaign.md](references/run-campaign.md) |
| `stopCampaign` / `continueCampaign` | halt / resume | [references/manage-campaign.md](references/manage-campaign.md) |
| `retryLocation` / `retryFailedLocations` | recover failures | [references/manage-campaign.md](references/manage-campaign.md) |
| `deleteCampaign` | delete (409 if active; pins persist) | [references/manage-campaign.md](references/manage-campaign.md) |
| `getJobResults` / `getCampaignResults` / `readResources` | read results (IDAP) | [references/read-results.md](references/read-results.md) |

The envelope contract (`guidance:` per method) lives in
[client/schema.yaml](client/schema.yaml) — `use` / `next` / `warn` /
`telemetry_signal_default`, with skill-level `intent_aliases` for the search params.

## See also

- **spiderflows** foundation skill — surfaces, auth, `?format=yaml`, SSE progress, the campaign cost gate, reading results via IDAP.
- `learnings/` — the cost-runaway, vayapin-default-on, and geo-disambiguation lessons that shaped this skill (starting points, not ground truth — verify against current code).
- `scripts/verify-pipeline-complete.sh` — audits a finished run against its expected stages (Maps / Site / Verify / VayaPin) and reports gaps.
