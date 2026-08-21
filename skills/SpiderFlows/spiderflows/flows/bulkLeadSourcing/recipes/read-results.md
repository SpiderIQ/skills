# Recipe: read a bulk run's results

**A bulk run's results are read in TWO steps, because they live in two places.**

```
GET /jobs/{job_id}/results         →  the PARENT.  A FUNNEL SUMMARY.
                                      How many were delivered, how many survived
                                      screening, what it cost, and WHERE the leads are.
                                      It has NO `businesses` array and never will.

  └─ data.children.job_ids[]        →  one job per surviving lead. Read EACH through
     GET /jobs/{child_id}/results      the SAME endpoint. THIS is where `businesses` is.
```

If you only read the parent you will see no leads and conclude the run produced
nothing. That is the single most common mistake against this flow, and it is what
`@spideriq/spiderflows` ≤ 0.10.0 told you to do.

## The three handles a bulk run gives you

```
bulk_job_id   the MANIFEST  — provenance, counts, the stored artifact digest
job_id        the PARENT    — poll this for status (there is NO bulk status route),
                              then read this for the funnel and the child pointers
campaign       bulk_<bulk_job_id>  — the campaign the per-lead jobs were fanned into
```

## Step 1 — wait for terminal

Poll `GET /jobs/{job_id}/status` (3–5 s minimum interval). The manifest walks
`pending → submitted → fanning_out → completed`. `submitted` means the provider
has the job; `fanning_out` means records are arriving and per-lead jobs are being
created.

## Step 2 — read the PARENT for the funnel, the money, and the pointers

```bash
curl "https://spideriq.ai/api/v1/jobs/{job_id}/results?format=yaml" \
  -H "Authorization: Bearer $SPIDERIQ_PAT"
```

`data` is a funnel summary. The three sections that matter:

| Section | Answers |
|---|---|
| `data.screening` | `provider_delivered` → `kept` / `dropped`, plus `drop_reasons` — **why** records were dropped |
| `data.cost` | `cost_usd`, `currency`, and `source_is_free` — the free-vs-unpriced discriminator |
| `data.children` | `job_ids[]` — the per-lead jobs. `job_ids_truncated`, `fanned_out_count`, `campaign_id`, and two endpoint templates |

Measured live on a completed run:

```yaml
screening:
  provider_delivered: 20
  kept: 0
  dropped: 20
  drop_reasons: { too_few_reviews: 20 }
cost:
  cost_usd: 0.0
  source_is_free: true
children:
  fanned_out_count: 0
  job_ids: []
```

### 🔴 `kept: 0` is an ANSWER, not an error

The run above is **healthy and finished**. Twenty records were purchased-or-fetched,
and all twenty were rejected by *the caller's own screening floor* — `drop_reasons`
says `too_few_reviews: 20`. Nothing broke, nothing was lost, and (here) nothing was
spent.

`drop_reasons` exists precisely so you never have to guess between:

- **"the filter rejected them"** — `dropped > 0` with reasons. A complete answer.
  Report it as *"the run returned 20 and your review floor kept 0"*, and offer to
  relax the floor.
- **"the pipeline died"** — `screening` **absent entirely**, which is what a run that
  never reached the parse stage looks like.

Reading `kept: 0` as breakage recreates the exact defect this recipe was rewritten
to fix.

## Step 3 — follow `children.job_ids` for the actual leads

Each child is read through the **same** endpoint, and a child **does** carry the
campaign envelope:

```bash
for id in $(… data.children.job_ids …); do
  curl "https://spideriq.ai/api/v1/jobs/$id/results?format=yaml" \
    -H "Authorization: Bearer $SPIDERIQ_PAT"
done
```

### The CHILD's envelope is identical to a campaign's — the parent's is not

Verified live against production children `1d169a58` and `97c44c7b`:

| Level | Result |
|---|---|
| top-level keys | **10 / 10 identical** |
| `data` keys | **4 / 4 identical** — `businesses`, `metadata`, `query`, `results_count` |
| business field names | **24 / 24 identical** |

So any parser, export or dashboard that reads campaign results reads a bulk
**child** with no change. **`metadata` is the one deliberate difference** — it
carries bulk provenance (`bulk: true`, `bulk_job_id`, `source`, `source_kind`)
where a campaign carries scrape knobs. Do not assert equality on `metadata`.

This table was attached to the *parent* in 0.10.0. The numbers were right; the
noun was wrong.

### The list is capped at 100

`job_ids` carries at most **100** ids — a run may fan out up to
`BULK_MAX_RECORDS_PER_JOB` (25,000) and inlining that many would be a
denial-of-service on the response. `job_ids_truncated` is stated on **every**
payload, true or false, so a short list can never be mistaken for a small run.

Past the cap, use the campaign aggregate instead of the ids:

```bash
curl "https://spideriq.ai/api/v1/jobs/spiderMaps/campaigns/bulk_<bulk_job_id>/workflow-results" \
  -H "Authorization: Bearer $SPIDERIQ_PAT"
```

`data.children.workflow_results_endpoint` gives you this path already built.

## Reading through IDAP

```bash
curl "https://spideriq.ai/api/v1/idap/businesses?campaign_id=bulk_<bulk_job_id>&include=emails,phones,domains,pins" \
  -H "Authorization: Bearer $SPIDERIQ_PAT"
```

⚠️ **Not verified for bulk runs.** A live check on 2026-08-21 found **zero** rows in
the tenant's normalized corpus carrying a bulk run's `source_job_id` or a `bulk_%`
`source_campaign_id`, while a bare `/idap/businesses` for the same tenant returned
rows. The cause is not established — it may be correct for a run whose only enabled
stage was `spidersite`. **Do not present IDAP-by-campaign as the bulk read path
until that is scoped.** Steps 2 + 3 above are the path that is measured to work.

## Gotchas

- 🔴 **`GET /jobs/spiderMaps/campaigns/{id}/jobs` lies for bulk.** It returns HTTP
  200 with `total: 2` and `jobs: []`. The count query `LEFT JOIN`s `jobs` while the
  row query INNER-joins `locations`, and a bulk child has `location_id IS NULL`
  because it is a per-LEAD row, not a geo-scoped one. Use `data.children.job_ids`,
  which is inlined for exactly this reason.

- 🔴 **`/api/v1/campaigns/{id}/…` does not exist.** That router is mounted at
  `/api/v1/jobs/spiderMaps/campaigns`. The bare path 404s for every campaign, bulk
  or not.

- **Coordinates are nested, and the keys are the long names.**
  `coordinates: { latitude, longitude }` — **not** `lat`/`lng`, and not top-level.
  Reading either the flat names or the short names yields `undefined` and looks
  like missing geo data.

- **Emails in the output did NOT come from the provider.** Contact enrichment is
  never requested from the source (`contact_enrichment=false`) — emails and phones
  are produced by our SpiderSite / SpiderVerify stages. Their presence is evidence
  the chain ran; their **absence is not evidence it did not**. Measured: a run with
  `kept: 2` and both children fetched carried zero contact data, and the campaign
  aggregate showed `sites_completed: 2` — SpiderSite *did* run, on sites that
  genuinely had no contact data. Cross-check
  `workflow_results.workflow_progress.sites_completed` before calling it a false green.

- **`workflow_progress` is the trustworthy half of `workflow-results`.** On the same
  response, `total_businesses`, `total_emails_found` and `locations` read `0` / `[]`
  for a bulk campaign — they are computed through the same `locations` join as the
  broken `/jobs` route. `workflow_progress.*` is not, and reported `sites_completed: 2`
  correctly.

- **Dedup is per bulk job.** The key is `(bulk_job_id, canonical_key)` — for
  `google_maps`, `canonical_key` is the `place_id`. Two *separate* bulk runs can
  each return the same business; dedup does not span runs.

- **The stored artifact is a digest reference, not the raw body.** The manifest
  records a storage key plus a byte count and a sha256 — the flat provider payload
  is not inlined into the row. Fetch it by key if you need the raw seed.

- **A 200 with a full record is not proof the whole chain ran.** See
  `learnings/2026-08-09-a-completed-flow-can-still-have-failed/`.

## Verify

Run the bundled script — it does all of the above and prints a verdict:

```bash
SPIDERIQ_PAT="client_id:api_key:api_secret" ./scripts/verify-bulk-complete.sh <parent_job_id>
```

By hand:

- `GET /jobs/{job_id}/status` = `completed`.
- Parent `data.screening` present. If `kept: 0`, `drop_reasons` explains it — **stop
  here, that is the answer**.
- If `kept > 0`, `data.children.job_ids` is non-empty, and each child fetched
  through `/jobs/{child_id}/results` returns `data.businesses` with the 24 campaign
  field names.
- `workflow_progress.sites_completed` matches the number of leads, confirming the
  site stage ran even when it found nothing.
