# Recipe: run a bulk lead-sourcing job

One provider job covering many search terms across many locations → one flat
result set → deduplicated → one downstream job per lead.

Read [bulk-vs-campaign.md](bulk-vs-campaign.md) first if you have not decided
between this and `createCampaign`. Read [cost-and-limits.md](cost-and-limits.md)
**before** submitting — this spends provider credits and cannot be unbought.

```
POST /bulk-lead-sourcing/submit  →  202 (manifest written, provider NOT called)
        ↓  bulk worker
   submit → poll → fetch → parse → dedup → fan-out
        ↓  one job per lead
   SpiderSite → SpiderVerify → VayaPin       (identical to a campaign)
```

## Steps

1. **Build the buy order.** `source.queries` are **bare** terms; `source.geo[].label`
   carries the place. The effective search list is `queries x geo labels`.

2. **Set `workflow` explicitly.** `settings.workflow` is the same `WorkflowConfig`
   a campaign uses. **`vayapin` publishes a permanent public profile per lead** —
   never leave it to a default when the user asked for a data-only list.

3. **Submit.**

   ```bash
   curl -X POST "https://spideriq.ai/api/v1/bulk-lead-sourcing/submit" \
     -H "Authorization: Bearer $SPIDERIQ_PAT" \
     -H "Content-Type: application/json" \
     -d '{
       "source": {
         "provider": "outscraper",
         "source_kind": "google_maps",
         "queries": ["restaurants", "cafes"],
         "geo": [
           { "label": "Atlanta, Georgia, USA", "country_code": "US" },
           { "label": "Savannah, Georgia, USA", "country_code": "US" }
         ],
         "limits": { "max_records_per_query": 100 }
       },
       "settings": {
         "workflow": {
           "spidersite":   { "enabled": true },
           "spiderverify": { "enabled": true },
           "vayapin":      { "enabled": false },
           "smartlead":    { "enabled": false }
         }
       }
     }'
   ```

   Response (`202`):

   ```json
   {
     "bulk_job_id": "051c62ab-ef51-470a-a8f0-4abdd6b14f90",
     "job_id": "7ae3b20d-a9ee-4601-a6ed-317885f6a3aa",
     "provider": "outscraper",
     "source_kind": "google_maps",
     "status": "pending",
     "estimated_queries": 4,
     "estimated_records": 400,
     "estimated_cost_usd": null,
     "message": "..."
   }
   ```

   **`status` is always `"pending"` and the provider has not been called yet.**
   The 202 means *accepted and gated*, not *bought*.

4. **Watch.** Poll `GET /jobs/{job_id}/status` no faster than every 3–5s.
   **There is no bulk-specific status route** — the parent `job_id` from the 202
   is what you poll. The manifest walks
   `pending → submitted → fanning_out → completed`.

5. **Read — in TWO steps.** See [read-results.md](read-results.md). The parent
   `job_id` returns a **funnel summary** (`screening` / `cost` / `children`) and
   never carries `businesses`; the per-lead rows are in the jobs listed at
   `data.children.job_ids`, each read through the same endpoint and each
   carrying the campaign envelope. The fan-out lands under a campaign named
   `bulk_<bulk_job_id>`.

## Key fields

| Field | Required | Notes |
|---|---|---|
| `source.provider` | ✅ | registered adapter, e.g. `outscraper` |
| `source.source_kind` | ✅ | `google_maps` \| `linkedin_company` — **bounds stage eligibility** |
| `source.queries[]` | ✅ | 1–1000 **bare** terms |
| `source.geo[]` | — | 0–1000. `label` places the search; lat/lng steer the centre |
| `source.limits.max_records_per_query` | — | 1–100 000; omit for the platform default |
| `source.limits.max_total_records` | — | 1–1 000 000, whole-job ceiling |
| `source.filters` | — | provider-specific; refused if it would overwrite a field the request owns |
| `source.language` | — | default `en` |
| `settings.workflow` | — | `WorkflowConfig` verbatim — same shape as a campaign |
| `priority` | — | 0–10 (default 5), for the fanned-out leads |
| `test` | — | route to test queues |

## Gotchas

- **`country_code` and `region` do NOT place a search.** They are locale hints.
  A `geo` entry with only `country_code: "US"` and no `label` does not target the
  US — it just tells the provider which locale to answer in. Put the place in
  `label`, or give an explicit `latitude`/`longitude`.

- **`source_kind` bounds the stages, and violating it is a 422, not a skip.**
  `google_maps` can feed every stage. `linkedin_company` can never feed
  `vayapin` — a LinkedIn company has no street address and no `place_id`, so a
  pin would be garbage. Enabling it is rejected at submit; it is deliberately
  **not** a silent skip, which would look like a run that quietly did less.

- **The searches multiply.** `queries x geo labels`. Three queries and four
  labels is twelve searches, not four. Check `estimated_queries` in the 202
  against what you meant.

- **`estimated_cost_usd` can be `null`.** That means no unit cost is configured
  for the provider — **not** that the run is free. When it is null the
  record-count ceiling is the only arm guarding the run.

- **Coordinates come back nested.** In the result records, coordinates are under
  `coordinates: { lat, lng }` — there are no top-level `latitude`/`longitude`
  fields. (Verified live.)

- **The provider is not asked for contacts.** Contact enrichment is off at the
  provider (`contact_enrichment=false`); emails and phones are found by
  *our* SpiderSite/SpiderVerify stages. So a bulk record with verified emails is
  proof the chain ran — the purchased seed never contained them.

## Verify

- 202 with a `bulk_job_id` **and** a `job_id` → accepted and gated.
- `estimated_queries` is at most `len(queries) x max(len(geo labels), 1)` → the
  expansion is what you intended. It can be *lower*: the expansion is
  `"{query}, {label}"` and identical strings are collapsed, so overlapping
  query/label wording silently costs you less than the naive product.
- `GET /jobs/{job_id}/status` reaches `completed` → fan-out done.
- Parent results carry `data.screening` → the funnel. `kept: 0` with
  `drop_reasons` is an **answer**, not a failure.
- Each id in `data.children.job_ids` carries `data.businesses[]` in the campaign
  envelope → chain ran.
- `scripts/verify-bulk-complete.sh <job_id>` → per-stage audit. **Pass the
  PARENT `job_id`, not the `bulk_job_id`** — the latter has no job route and the
  script will tell you so.
