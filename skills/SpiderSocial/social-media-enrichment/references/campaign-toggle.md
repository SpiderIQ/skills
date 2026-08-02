# Enrich a whole lead campaign (the workflow toggle)

Running this skill one business at a time is right for a targeted rescue. For a
WHOLE lead list, don't loop the standalone job — turn on the
`social_media_enrichment` stage on a `lead-search` / campaign run, and every
business that finishes with **no verified email** is enriched automatically, then
re-verified and merged back.

## Steps

The toggle lives in the `workflow` block of a `lead-search` (single location) or
campaign submission. It is **default ON** for entitled accounts — you send
`enabled: false` only to opt OUT.

```bash
curl -X POST "https://spideriq.ai/api/v1/lead-search" \
  -H "Authorization: Bearer $SPIDERIQ_PAT" \
  -H "Content-Type: application/json" \
  -d '{
        "search_query": "plumbers",
        "country_code": "DE",
        "location": "Berlin",
        "workflow": {
          "social_media_enrichment": { "enabled": true }
        }
      }'
```

Opt out (data-only, no enrichment):

```json
{ "workflow": { "social_media_enrichment": { "enabled": false } } }
```

The same `workflow.social_media_enrichment` block is accepted by the
`create_campaign` / `searchLeads` methods in the `lead-search` and
`run-enrichment-pipeline` skills.

## Gotchas

- **Default ON, entitlement-gated.** An entitled account's campaigns enrich
  unless you send `enabled: false`. A non-entitled account's campaigns never run
  the stage regardless of the flag — so the toggle is a no-op without the plan.
- **Only no-email businesses are enriched.** The stage runs only for businesses
  that finished the pipeline with no verified email — it never spends a credit on
  a business that already has one.
- **Recovered contacts flow through the normal pipeline.** A recovered email is
  re-verified and merged into that lead, so it lands in the campaign's normalized
  data (businesses / contacts / emails / phones) that `internet-data-access`
  (IDAP) reads — no separate results call per business.

## Verify

- The campaign submission is accepted (a `job_id` / `campaign_id` comes back).
- After the run completes, businesses that previously had no email but had social
  profiles now carry a verified email in the campaign's normalized contacts
  (read via `internet-data-access`).

## When to use which

| You have… | Use |
|---|---|
| ONE business with social profiles but no email | this skill's standalone `submitJob` (`run-social-enrichment.md`) |
| A whole city / list to enrich in bulk | the campaign toggle here (`lead-search` / `run-enrichment-pipeline`) |
