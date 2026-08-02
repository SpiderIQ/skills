---
name: run-enrichment-pipeline
version: "1.1.0"
description: >
  Enrichment pipeline management — create and manage lead enrichment campaigns, retrieve results, control execution, and deduplicate records.

category: data-collection
requires_auth: true
requires_brand: true
triggers:
  - enrichment
  - pipeline
  - campaign
  - windmill
client: run-enrichment-pipeline
client_version: "1.1.0"
metadata:
  openclaw:
    primaryEnv: OPVS_PAT
---

# run-enrichment-pipeline #data_collection

orchestrate multi-step enrichment campaigns — Maps search, website scrape, email verify in automated sequence

/#scrape-google-maps → single one-off Maps search
/#lead-enrichment → manual lead board management
/#campaigns → outreach campaigns (email sequences, not data enrichment)

## Chain
estimateCampaign (preflight) → createCampaign → getCampaignStatus (poll 10s) → getCampaignResults
getCampaignResults → deduplicate (remove duplicates before import)

## Limits
$concurrent:plan-tiered active campaigns — Free 1 / Starter 1 / Growth 3 / Pro unlimited $speed:parallel locations/campaign — Free 1seq / Starter 5 / Growth 15 / Pro 50 $batch:start with 50-100 leads to validate pipeline

## Pitfalls
- estimateCampaign BEFORE createCampaign — exact location + per-stage job counts, no rows written, not billed
- At the concurrent cap createCampaign returns 429 MAX_CAMPAIGNS_PER_CLIENT (envelope CTA → /dashboard/plans) — finish/stop a running campaign or upgrade; no queue, no Retry-After
- Higher tiers run more locations in parallel (speed), not more results — Free is sequential
- Start small (50-100 leads) to validate before scaling to thousands
- Always deduplicate results before importing to board
- Campaigns can run for hours — set expectations with user

## Case $t:2026-03
Berlin SaaS companies: Campaign(SaaS Berlin)→200 Maps results→Site(140)→89 emails→Verify→67 valid→Dedup→61 unique. 45min.

## Methods

- `estimateCampaign(country_code, filter?, max_results?, workflow?)` — Pre-flight estimate: returns `total_locations`, per-stage billable-job counts, `total_billable_jobs`, and `requires_upgrade`. Pure read — writes no rows, not billed, not a dispatcher submission. Call before createCampaign to make a Proceed/Upgrade decision. → createCampaign
- `createCampaign(search_query, country_code?, workflow?)` — Create a new enrichment campaign. Defines the search query, target country, and optional workflow configuration. → getCampaignStatus (poll every 10s) [WARN: start with max_results 50-100 for first run] [WARN: at the plan's concurrent-campaign cap this returns 429 MAX_CAMPAIGNS_PER_CLIENT with a /dashboard/plans upgrade CTA — finish/stop a running campaign or upgrade]
- `listCampaigns(status?, page?, pageSize?)` — List all enrichment campaigns, optionally filtered by status with pagination.
- `getCampaignStatus(campaign_id)` — Get the current status and progress of a specific enrichment campaign.
- `getCampaignResults(campaign_id)` — Retrieve the enriched results from a completed or running campaign.
- `stopCampaign(campaign_id)` — Stop a running enrichment campaign. Already-processed results are preserved. [WARN: stopped campaigns can be resumed with continueCampaign]
- `continueCampaign(campaign_id)` — Resume a previously stopped enrichment campaign from where it left off. → getCampaignStatus (poll every 10s)
- `deduplicate(records, match_fields)` — Fuzzy-match deduplicate a set of records based on specified fields. Returns unique records with similarity scores.
