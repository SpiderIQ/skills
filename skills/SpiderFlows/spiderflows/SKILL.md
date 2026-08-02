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
  plus each flow's payload and recipes. It implements the lead /
  local-business pipeline (Maps → Site → Verify → VayaPin), sold as both
  leadSearch and localSeo; and the company-intel pipeline
  (flow:perplexity-site-companydata-people, marketed as Company Intel) — one
  company name in, a full account brief out (domain, registry filing, LinkedIn
  team, verified emails). Trigger company-intel on: "research <company>",
  "company intel", "account brief", "enrich this company / vendor list", "KYC
  enrichment", "find a company's domain / registry number / LinkedIn / employees".
  And the LinkedIn-people flow (flow:linkedinProfiles): one endpoint, three modes
  — enrich a profile URL, find profiles by a search query, or pull a company's
  employees. Trigger linkedinProfiles on: "enrich this LinkedIn profile", "find
  people on LinkedIn", "look up a LinkedIn profile", "who works at <company>",
  "pull a company's employees / team from LinkedIn", "search LinkedIn for <title>".
  And commerce funnels (flow:commerce): sell a product through a checkout + one-time-offer
  (OTO) funnel that lands a Stripe-canonical order. Trigger commerce on: "build a tripwire
  funnel", "sell a product / one-time offer / upsell", "checkout funnel", "subscription
  funnel", "set up a commerce funnel", "read my orders / revenue". Commerce funnels are
  created by forking a template (funnel_template_apply), NOT by hand. More flows are added
  here as recipes.
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

The second flow — **company-intel** — goes the other way: you start from a
**company name** (not a place) and get back a full account brief.

```
flow:perplexity-site-companydata-people   (marketed as Company Intel)
Perplexity        SpiderSite        SpiderCompanyData   SpiderPeople     SpiderVerify
discover domain → crawl the site → registry filing →   LinkedIn team → verify the
+ LinkedIn URL    (emails, team)    (UK/US/EU registry)  (employees)     extracted emails
```

Run it for one company (an account brief) or a list of up to 50 (KYC / list
enrichment). It is a **single + batch** flow — there is no campaign / location
fan-out (that's the lead chain). Results come back as a per-company brief via
`GET /jobs/{job_id}/results`, with registry + LinkedIn also queryable as their own
IDAP types.

The third flow — **linkedinProfiles** — is people-first: you start from a LinkedIn
**profile URL**, a **search query**, or a **company URL**, and get LinkedIn people
records back.

```
flow:linkedinProfiles   (SpiderPeople — LinkedIn people)
profile  → enrich one profile URL         → full profile (experience, education)   [Bright Data]
search   → find profiles by a query       → shallow profile list (URL+headline)    [Bright Data SERP]
company  → extract a company's employees  → employee roster (titles, +email/skills) [Apify]
```

One endpoint (`POST /jobs/spiderPeople/submit`, `mode` selects the provider), three
modes — single jobs, **no campaign fan-out**. Read the people back via
`GET /jobs/{job_id}/results`, with `linkedin_profiles` + `contacts` also queryable
through IDAP. (This is *not* the account-and-proxy-gated Voyager LinkedIn search —
that's a separate service, out of scope here.)

The fourth flow — **commerce** — is the odd one out: it does not scrape or enrich. It
**sells a product** through a funnel and lands a real order.

```
flow:commerce   (kind='funnel' carrying checkout + oto nodes — Unified Funnels + Commerce P3)
checkout node → oto node → thank-you
(tripwire buy)  (accept = charge upsell off-session · decline = no-op)  (Stripe-canonical order)
```

You **create a commerce funnel by forking a template** (`funnel_template_apply`, one of
`single-product-checkout` / `tripwire-oto` / `subscription-checkout`) — never by hand, because the
graph validator enforces `OTO_REQUIRES_CHECKOUT` + `COMMERCE_NODE_LAYER`. Publish with
`live_mode=true`, walk the buyer path with Stripe TEST, and read orders back through the 4
`commerce_order_*` tools (`spideriq commerce orders …`). Stripe is the order-of-record (Medusa is
catalog/cart only). **You can author the whole funnel EXCEPT the product itself** — product
creation is the Medusa Admin UI today ([8.6c]). See
[flows/commerce-funnels/recipes/build-tripwire-oto.md](flows/commerce-funnels/recipes/build-tripwire-oto.md).

## Approach

- **Single location** — one city, one search. Fastest; use
  [flows/maps-site-verify-vayapin/recipes/run-single.md](flows/maps-site-verify-vayapin/recipes/run-single.md). Always safe on cost.
- **Campaign** — the same search across many locations (a country/region/population
  band). Use [flows/maps-site-verify-vayapin/recipes/run-campaign.md](flows/maps-site-verify-vayapin/recipes/run-campaign.md), and respect
  the cost gate first ([flows/maps-site-verify-vayapin/recipes/cost-check.md](flows/maps-site-verify-vayapin/recipes/cost-check.md)).
- **Manage / read** — stop, resume, retry, delete, and read results out
  through IDAP. See [flows/maps-site-verify-vayapin/recipes/manage-campaign.md](flows/maps-site-verify-vayapin/recipes/manage-campaign.md)
  and [flows/maps-site-verify-vayapin/recipes/read-results.md](flows/maps-site-verify-vayapin/recipes/read-results.md).

<HARD-GATE name="cost-budget">
Before submitting a **campaign**, know how many locations it will fan out to. A
`filter.mode` of `"all"` or `"cities_only"` over a whole country expands to *every*
city — one `(country: DE)` campaign once fanned to **1,733 locations** and burned
113 worker jobs in 23 seconds. If you are about to submit a country-wide campaign
without a `population` or `regions` narrowing, STOP: narrow the filter, or submit
and immediately check `total_locations` in the response and `stopCampaign` if it is
larger than intended. A single-location run is always safe — this gate is campaigns
only. ([flows/maps-site-verify-vayapin/recipes/cost-check.md](flows/maps-site-verify-vayapin/recipes/cost-check.md))
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
published pin. ([flows/maps-site-verify-vayapin/recipes/vayapin-export.md](flows/maps-site-verify-vayapin/recipes/vayapin-export.md))
</HARD-GATE>

<HARD-GATE name="smartlead-target-is-live-outreach">
`workflow.smartlead.enabled=true` pushes the campaign's **verified** leads into a
**live SmartLead outreach campaign** at completion — those contacts then get
**emailed** by that campaign's sequence. So: (1) NEVER guess the target — you MUST
discover `connection_id` (SpiderMail `listOutreachConnections`) and
`remote_campaign_id` (`listOutreachCampaigns`) and confirm the campaign name with
the user before enabling; (2) it requires `spiderverify.enabled=true` (only verified
emails export — leave verify ON); (3) it only fires when the run reaches a terminal
state. If the user just wants a lead *list* (not to send email yet), do NOT enable
smartlead. ([flows/maps-site-verify-vayapin/recipes/smartlead-export.md](flows/maps-site-verify-vayapin/recipes/smartlead-export.md))
</HARD-GATE>

## Rules (Non-Negotiable)

**Auth:** every call carries `Authorization: Bearer <client_id>:<api_key>:<api_secret>` (a PAT). CLI/MCP load it from `~/.spideriq/credentials.json`; for raw HTTP, never echo the secret into logs or chat. Your PAT is self-identifying (`spideriq_pat_<agent_ref>_<secret>`) and carries an `opvsAddress` (`<name>@opvs.run`) — you are ONE account, so re-auth from a new folder ROTATES it (never forks a ghost); `--as <opvs-address>` RECOVERs it on a fresh box.

**Never tight-loop:** after submit, poll status no faster than every 3–5 seconds, or use the SSE stream. Workers take seconds-to-minutes per location.

**Query construction differs by mode.** Single: put the location *inside* the query (`"plumbers in Berlin"`) or pass `location` — not both. Campaign: the query is *bare* (`"plumbers"`); location comes from `country_code` + `filter`. A city in both double-targets and wastes the run.

**Stages are opt-in past Maps.** `workflow.spidersite.enabled`, `workflow.spiderverify.enabled`, `workflow.vayapin.enabled` gate each stage. SpiderVerify and VayaPin both require SpiderSite (422 otherwise). Maps always runs. **SmartLead export** (`workflow.smartlead.enabled`) is a FINALIZE step, not a pipeline stage — it needs `spiderverify.enabled=true` (only verified leads export) and runs once, at terminal-close. See the `smartlead-target-is-live-outreach` HARD-GATE.

**Read results through IDAP, by `campaign_id`.** `GET /api/v1/idap/businesses?campaign_id=<id>&include=emails,phones,domains,pins`. Don't parse progress endpoints for data. (`pins` is read via `include`, not as a standalone type.)

**Stop before you delete.** `deleteCampaign` refuses (409) while a campaign has active jobs. Stop it, let in-flight jobs settle, then delete.

## Decision tree — pick a recipe

| The user wants to… | Read |
|---|---|
| understand the surfaces / auth / `?format=yaml` before the first call | [references/surfaces-and-auth.md](references/surfaces-and-auth.md) |
| run one city / one search (lead list or local SEO) | [flows/maps-site-verify-vayapin/recipes/run-single.md](flows/maps-site-verify-vayapin/recipes/run-single.md) |
| run a search across many locations (country / region / population band) | [flows/maps-site-verify-vayapin/recipes/run-campaign.md](flows/maps-site-verify-vayapin/recipes/run-campaign.md) |
| run a US campaign deep by ZIP code (one state at a time — "state = country") | [flows/maps-site-verify-vayapin/recipes/state-zip-campaign.md](flows/maps-site-verify-vayapin/recipes/state-zip-campaign.md) |
| check how big a campaign will be BEFORE submitting | [flows/maps-site-verify-vayapin/recipes/cost-check.md](flows/maps-site-verify-vayapin/recipes/cost-check.md) |
| stop / resume / retry / delete a campaign | [flows/maps-site-verify-vayapin/recipes/manage-campaign.md](flows/maps-site-verify-vayapin/recipes/manage-campaign.md) |
| auto-export a campaign's verified leads into a SmartLead outreach campaign | [flows/maps-site-verify-vayapin/recipes/smartlead-export.md](flows/maps-site-verify-vayapin/recipes/smartlead-export.md) |
| read the businesses, emails, phones, and pins a run produced | [flows/maps-site-verify-vayapin/recipes/read-results.md](flows/maps-site-verify-vayapin/recipes/read-results.md) |
| research ONE company → a full account brief (domain, registry, LinkedIn, emails) | [flows/perplexity-site-companydata-people/recipes/run-single.md](flows/perplexity-site-companydata-people/recipes/run-single.md) |
| enrich a LIST of companies (KYC / list enrichment, up to 50) | [flows/perplexity-site-companydata-people/recipes/run-batch.md](flows/perplexity-site-companydata-people/recipes/run-batch.md) |
| read a company-intel run's brief (registry / LinkedIn / emails via IDAP) | [flows/perplexity-site-companydata-people/recipes/read-results.md](flows/perplexity-site-companydata-people/recipes/read-results.md) |
| scrape ONE website → a contact + intelligence profile (emails, socials, team, compendium) | [flows/siteScraper/recipes/run-single.md](flows/siteScraper/recipes/run-single.md) |
| scrape a LIST of websites (1–500 URLs) | [flows/siteScraper/recipes/run-batch.md](flows/siteScraper/recipes/run-batch.md) |
| read a site crawl's profile (results + contacts via IDAP) | [flows/siteScraper/recipes/read-results.md](flows/siteScraper/recipes/read-results.md) |
| verify emails you ALREADY have — one address or a list of ≤100 | [flows/emailVerify/recipes/run-single.md](flows/emailVerify/recipes/run-single.md) |
| read an emailVerify run's verdicts (status / score / flags per email) | [flows/emailVerify/recipes/read-results.md](flows/emailVerify/recipes/read-results.md) |
| enrich ONE LinkedIn profile URL → a full profile | [flows/linkedinProfiles/recipes/run-profile.md](flows/linkedinProfiles/recipes/run-profile.md) |
| find LinkedIn profiles from a search query (shallow list) | [flows/linkedinProfiles/recipes/run-search.md](flows/linkedinProfiles/recipes/run-search.md) |
| extract a company's employees from its LinkedIn page | [flows/linkedinProfiles/recipes/run-company.md](flows/linkedinProfiles/recipes/run-company.md) |
| read a linkedinProfiles run's people (job results / IDAP) | [flows/linkedinProfiles/recipes/read-results.md](flows/linkedinProfiles/recipes/read-results.md) |
| build a commerce funnel that sells a product (tripwire + one-time-offer upsell) | [flows/commerce-funnels/recipes/build-tripwire-oto.md](flows/commerce-funnels/recipes/build-tripwire-oto.md) |
| build a simple one-product checkout funnel (no upsell) | [flows/commerce-funnels/recipes/single-product-checkout.md](flows/commerce-funnels/recipes/single-product-checkout.md) |
| build a subscription / recurring-plan funnel with an upgrade OTO | [flows/commerce-funnels/recipes/subscription-checkout.md](flows/commerce-funnels/recipes/subscription-checkout.md) |
| read commerce orders + revenue a funnel produced | [flows/commerce-funnels/recipes/read-orders.md](flows/commerce-funnels/recipes/read-orders.md) |
| understand poll-vs-SSE progress and realistic timing | [references/run-modes-and-progress.md](references/run-modes-and-progress.md) |
| watch a run with live events instead of polling — react to the stream, read the sink once on the terminal `campaign.terminal` / `job.completed` event | [recipes/watch-a-run.md](recipes/watch-a-run.md) (event surface: [references/events-stream.md](references/events-stream.md)) |

## Per-stage settings (quick map — full detail in the reference)

| Stage | Key settings | Reference |
|---|---|---|
| Maps | `search_query`, `country_code`, `max_results` (1–500), `lang` | [flows/maps-site-verify-vayapin/recipes/per-stage-settings.md](flows/maps-site-verify-vayapin/recipes/per-stage-settings.md) |
| Site | `mode` (contacts / compendium / leads / full), `max_pages`, `extract_team`, CHAMP `product_description`+`icp_description` | [flows/maps-site-verify-vayapin/recipes/per-stage-settings.md](flows/maps-site-verify-vayapin/recipes/per-stage-settings.md) |
| Verify | `check_gravatar`, `check_dnsbl`, `max_emails_per_business` | [flows/maps-site-verify-vayapin/recipes/per-stage-settings.md](flows/maps-site-verify-vayapin/recipes/per-stage-settings.md) |
| VayaPin | `enabled` (path-dependent default — see the HARD-GATE) | [flows/maps-site-verify-vayapin/recipes/vayapin-export.md](flows/maps-site-verify-vayapin/recipes/vayapin-export.md) |
| SmartLead (finalize) | `enabled`, `connection_id`, `remote_campaign_id`, `only_with_vayapin_seo` — auto-export verified leads at completion | [flows/maps-site-verify-vayapin/recipes/smartlead-export.md](flows/maps-site-verify-vayapin/recipes/smartlead-export.md) |

## Methods (native tool calls — opvsHUB & marketplace)

This skill ships as typed tool calls generated from `client/schema.yaml`:

| Method | Does | Recipe |
|---|---|---|
| `searchLeads` | run one location (single) | [flows/maps-site-verify-vayapin/recipes/run-single.md](flows/maps-site-verify-vayapin/recipes/run-single.md) |
| `createCampaign` | run across many locations | [flows/maps-site-verify-vayapin/recipes/run-campaign.md](flows/maps-site-verify-vayapin/recipes/run-campaign.md) |
| `listCampaigns` / `getCampaignStatus` / `getJobStatus` | list + poll progress | [references/run-modes-and-progress.md](references/run-modes-and-progress.md) |
| `stopCampaign` / `continueCampaign` / `updateCampaign` | halt / resume / edit config | [flows/maps-site-verify-vayapin/recipes/manage-campaign.md](flows/maps-site-verify-vayapin/recipes/manage-campaign.md) |
| `retryLocation` / `retryFailedLocations` | recover failures | [flows/maps-site-verify-vayapin/recipes/manage-campaign.md](flows/maps-site-verify-vayapin/recipes/manage-campaign.md) |
| `deleteCampaign` | delete (409 if active; pins persist) | [flows/maps-site-verify-vayapin/recipes/manage-campaign.md](flows/maps-site-verify-vayapin/recipes/manage-campaign.md) |
| `getJobResults` / `getCampaignResults` / `readResources` | read results (IDAP) | [flows/maps-site-verify-vayapin/recipes/read-results.md](flows/maps-site-verify-vayapin/recipes/read-results.md) |
| `researchCompany` | research ONE company (account brief) | [flows/perplexity-site-companydata-people/recipes/run-single.md](flows/perplexity-site-companydata-people/recipes/run-single.md) |
| `researchCompaniesBatch` | enrich a LIST of companies (≤50, KYC) | [flows/perplexity-site-companydata-people/recipes/run-batch.md](flows/perplexity-site-companydata-people/recipes/run-batch.md) |
| `searchMaps` | scrape Google Maps for one query — businesses only, no emails (Maps-only) | [flows/mapsSearch/recipes/run-single.md](flows/mapsSearch/recipes/run-single.md) |
| `scrapeSite` | crawl ONE website (contact + intelligence profile) | [flows/siteScraper/recipes/run-single.md](flows/siteScraper/recipes/run-single.md) |
| `scrapeSitesBatch` | crawl a LIST of websites (1–500 URLs) | [flows/siteScraper/recipes/run-batch.md](flows/siteScraper/recipes/run-batch.md) |
| `verifyEmails` | verify one email (single) or a list (≤100, batch) | [flows/emailVerify/recipes/run-single.md](flows/emailVerify/recipes/run-single.md) |
| `findPeople` | LinkedIn people — enrich a profile URL / search by query / a company's employees (`mode`) | [flows/linkedinProfiles/recipes/run-profile.md](flows/linkedinProfiles/recipes/run-profile.md) |
| `lookupCompanyRegistry` | look up ONE company in a public registry — standalone, no chain (search / lookup / vat) | [flows/companyRegistry/recipes/run-single.md](flows/companyRegistry/recipes/run-single.md) |

The envelope contract (`guidance:` per method — `use` / `next` / `warn` /
`telemetry_signal_default`, plus skill-level `intent_aliases`) lives in
[client/schema.yaml](client/schema.yaml).

## References (loaded on demand)

**Shared (read first in a session):**
- **[references/surfaces-and-auth.md](references/surfaces-and-auth.md)** — surfaces, Bearer PAT, `?format=yaml|md`.
- **[references/run-modes-and-progress.md](references/run-modes-and-progress.md)** — single vs campaign, poll vs SSE, timing.
- **[references/reading-results.md](references/reading-results.md)** — the IDAP read surface (resource types, `include`, paging).
- **[references/events-stream.md](references/events-stream.md)** — the live SSE event stream: endpoint, `?token=`/`?campaign_id=`/`?job_id=`, full event vocabulary (incl. the definitive `campaign.terminal`), framing, JS + Python snippets.
- **[recipes/watch-a-run.md](recipes/watch-a-run.md)** — listen-don't-poll: open the stream before submit, react, read the durable sink once on the terminal event.

**flow:maps-site-verify-vayapin:**
- **[flows/maps-site-verify-vayapin/recipes/run-single.md](flows/maps-site-verify-vayapin/recipes/run-single.md)** · **[flows/maps-site-verify-vayapin/recipes/run-campaign.md](flows/maps-site-verify-vayapin/recipes/run-campaign.md)** · **[flows/maps-site-verify-vayapin/recipes/cost-check.md](flows/maps-site-verify-vayapin/recipes/cost-check.md)** — submit.
- **[flows/maps-site-verify-vayapin/recipes/manage-campaign.md](flows/maps-site-verify-vayapin/recipes/manage-campaign.md)** — stop / resume / retry / delete.
- **[flows/maps-site-verify-vayapin/recipes/read-results.md](flows/maps-site-verify-vayapin/recipes/read-results.md)** — read this chain's results.
- **[flows/maps-site-verify-vayapin/recipes/per-stage-settings.md](flows/maps-site-verify-vayapin/recipes/per-stage-settings.md)** — every setting per stage. **Read before composing a non-trivial `workflow` block.**
- **[flows/maps-site-verify-vayapin/recipes/vayapin-export.md](flows/maps-site-verify-vayapin/recipes/vayapin-export.md)** — what vayapin publishes, the opt-out, verifying pins.
- **[flows/maps-site-verify-vayapin/recipes/campaign-results-shape.md](flows/maps-site-verify-vayapin/recipes/campaign-results-shape.md)** — the fields a finished business record carries.

**flow:perplexity-site-companydata-people (Company Intel):**
- **[flows/perplexity-site-companydata-people/recipes/run-single.md](flows/perplexity-site-companydata-people/recipes/run-single.md)** · **[flows/perplexity-site-companydata-people/recipes/run-batch.md](flows/perplexity-site-companydata-people/recipes/run-batch.md)** — submit (one company / a list of ≤50).
- **[flows/perplexity-site-companydata-people/recipes/read-results.md](flows/perplexity-site-companydata-people/recipes/read-results.md)** — read the account brief (registry + LinkedIn are standalone IDAP types).
- **[flows/perplexity-site-companydata-people/recipes/per-stage-settings.md](flows/perplexity-site-companydata-people/recipes/per-stage-settings.md)** — every `config` setting per stage. **Read before composing a non-trivial `config`.**
- **[flows/perplexity-site-companydata-people/recipes/results-shape.md](flows/perplexity-site-companydata-people/recipes/results-shape.md)** — the fields a finished company brief carries.

**flow:siteScraper (Site Scraper):**
- **[flows/siteScraper/recipes/run-single.md](flows/siteScraper/recipes/run-single.md)** · **[flows/siteScraper/recipes/run-batch.md](flows/siteScraper/recipes/run-batch.md)** — submit (one URL via `/jobs/spiderSite/submit` / a list of ≤500 via the Flows facade).
- **[flows/siteScraper/recipes/read-results.md](flows/siteScraper/recipes/read-results.md)** — read the profile (`/jobs/{id}/results`; contacts auto-sync to IDAP, scope by `?domain=`).
- **[flows/siteScraper/recipes/results-shape.md](flows/siteScraper/recipes/results-shape.md)** — the fields a finished site-crawl record carries (emails are extracted, NOT verified).
- **[flows/siteScraper/recipes/crawl-options.md](flows/siteScraper/recipes/crawl-options.md)** — every crawl knob (mode, AI opt-ins, compendium, custom prompt). **Read before composing a non-trivial crawl.**
**flow:emailVerify:**
- **[flows/emailVerify/recipes/run-single.md](flows/emailVerify/recipes/run-single.md)** · **[flows/emailVerify/recipes/run-batch.md](flows/emailVerify/recipes/run-batch.md)** — submit (one email / a list of ≤100). Standalone verifier for emails you already have.
- **[flows/emailVerify/recipes/read-results.md](flows/emailVerify/recipes/read-results.md)** — read the verdicts (single is **bulk-of-1** → `results[0]`).
- **[flows/emailVerify/recipes/results-shape.md](flows/emailVerify/recipes/results-shape.md)** — the fields a verified email carries (status / score / flags / domain / dnsbl).
- **[flows/emailVerify/recipes/verification-options.md](flows/emailVerify/recipes/verification-options.md)** — the payload toggles. **Read before composing a non-default request.**
**flow:linkedinProfiles (LinkedIn people):**
- **[flows/linkedinProfiles/recipes/run-profile.md](flows/linkedinProfiles/recipes/run-profile.md)** · **[flows/linkedinProfiles/recipes/run-search.md](flows/linkedinProfiles/recipes/run-search.md)** · **[flows/linkedinProfiles/recipes/run-company.md](flows/linkedinProfiles/recipes/run-company.md)** — submit (one profile URL / a search query / a company's employees).
- **[flows/linkedinProfiles/recipes/read-results.md](flows/linkedinProfiles/recipes/read-results.md)** — read the people (job aggregate; `linkedin_profiles` + `contacts` via IDAP).
- **[flows/linkedinProfiles/recipes/per-mode-settings.md](flows/linkedinProfiles/recipes/per-mode-settings.md)** — every field per mode + the `profile_mode` cost tiers. **Read before composing a non-trivial request.**
- **[flows/linkedinProfiles/recipes/results-shape.md](flows/linkedinProfiles/recipes/results-shape.md)** — the fields a finished profile / search / employee record carries.

## See also

- `flows/*/learnings/` — per-flow lessons (cost-runaway / vayapin-default-on / geo-disambiguation for the lead chain; hints-skip-stages / registry-coverage / partial-results / email-score for company-intel; bulk-of-1 / valid-can-score-low / unknown-not-invalid / slow-by-design / from-email-hello-name-deliverability / status-taxonomy for emailVerify) — starting points, not ground truth; verify against current code.
- `flows/maps-site-verify-vayapin/scripts/verify-pipeline-complete.sh` — audits a finished lead run against its expected stages.
- `flows/perplexity-site-companydata-people/scripts/verify-intel-complete.sh` — audits a finished company-intel run against its five stages.
- `flows/siteScraper/scripts/verify-site-complete.sh` — audits a finished site crawl (pages crawled, contacts, which optional sections landed).
- `flows/emailVerify/scripts/verify-emails-complete.sh` — audits a finished emailVerify run (per-status breakdown; flags high `unknown` / not-completed).
- `flows/linkedinProfiles/scripts/verify-people-complete.sh` — audits a finished linkedinProfiles run against the mode it ran (profile / search / company).
