# Recipe: read a bulk run's results

A bulk run's output is **the campaign envelope, unchanged**. If you already know
how to read a campaign, you know how to read this — the differences are in
*where* the run lives and *what the metadata says*, never in the record shape.

## The three handles a bulk run gives you

```
bulk_job_id   the MANIFEST  — provenance, counts, the stored artifact digest
job_id        the PARENT    — poll this for status (there is NO bulk status route)
campaign       bulk_<bulk_job_id>  — where the fanned-out per-lead jobs live
```

## Steps

1. **Wait for terminal.** Poll `GET /jobs/{job_id}/status` (3–5s minimum
   interval). The manifest walks `pending → submitted → fanning_out → completed`.
   `submitted` means the provider has the job; `fanning_out` means records are
   arriving and per-lead jobs are being created.

2. **Read the per-lead results** exactly as for a campaign:

   ```bash
   curl "https://spideriq.ai/api/v1/jobs/{job_id}/results?format=yaml" \
     -H "Authorization: Bearer $SPIDERIQ_PAT"
   ```

3. **Or read through IDAP by campaign**, which is the better path for anything
   list-shaped:

   ```bash
   curl "https://spideriq.ai/api/v1/idap/businesses?campaign_id=bulk_<bulk_job_id>&include=emails,phones,domains,pins" \
     -H "Authorization: Bearer $SPIDERIQ_PAT"
   ```

## The envelope is identical to a campaign's

Verified live against two production campaign runs:

| Level | Result |
|---|---|
| top-level keys | **10 / 10 identical** |
| `data` keys | **4 / 4 identical** — `businesses`, `metadata`, `query`, `results_count` |
| business field names | **24 / 24 identical** |

So any parser, export, or dashboard that reads campaign results reads bulk
results with no change. **`metadata` is the one deliberate difference** — it
carries bulk provenance (provider, source kind, manifest linkage) where a
campaign carries scrape knobs. Do not assert equality on `metadata`.

## Gotchas

- **Coordinates are nested.** `coordinates: { lat, lng }`. There are no
  top-level `latitude` / `longitude` fields on a business record. Reading the
  flat names yields `undefined` and looks like missing geo data.

- **Emails in the output did NOT come from the provider.** Contact enrichment is
  never requested from the source (`contact_enrichment=false`) — emails and
  phones are produced by our SpiderSite / SpiderVerify stages. So their presence
  is evidence the chain ran, and their *absence* means the site stage found
  nothing, not that the purchase was thin.

- **Dedup is per bulk job.** The key is `(bulk_job_id, canonical_key)` — for
  `google_maps`, `canonical_key` is the `place_id`. Two *separate* bulk runs can
  each return the same business; dedup does not span runs.

- **The stored artifact is a digest reference, not the raw body.** The manifest
  records a storage key plus a byte count and a sha256 — the flat provider
  payload is not inlined into the row. Fetch it by key if you need the raw seed.

- **A 200 with a full record is not proof the whole chain ran.** See
  `learnings/2026-08-09-a-completed-flow-can-still-have-failed/`. Cross-check
  `campaign_workflow_jobs > 0` for the fan-out campaign when provenance matters.

## Verify

- `GET /jobs/{job_id}/status` = `completed`.
- `data.businesses[]` non-empty and each carries the 24 campaign field names.
- IDAP by `campaign_id=bulk_<bulk_job_id>` returns the same businesses.
- Verified emails present → SpiderSite + SpiderVerify demonstrably ran (the seed
  could not have contained them).
