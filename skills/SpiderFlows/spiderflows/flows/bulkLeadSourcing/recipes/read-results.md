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

Poll `GET /jobs/{job_id}/status` (3–5 s minimum interval). The manifest walks:

```
pending → submitted → polling → ready → fetching → parsing → fanning_out → enriching → completed
```

with `partial`, `failed` and `cancelled` as the other terminal states.
`submitted` means the source has the job; `fanning_out` means records are
arriving and per-lead jobs are being created; **`enriching` means fan-out is done
and the run is waiting on its leads.**

### 🔴 A long `enriching` is NOT a stuck run — do not report it as one

This is the single most likely way to file a false finding against this flow.

```
  what you see        status: enriching, unchanged for hours
  what you conclude   the run is stuck
  what is true        fan-out is paced against the client's own per-hour job
                      quota, so 21,000 records at 500 jobs/hour is ~42 HOURS
                      of legitimate work
```

The run is **not** closed by a timer. It stays `enriching` while
`campaign_locations` still holds non-terminal rows, and closes when its *leads*
finish. Keep polling; say "still enriching, N outstanding", never "stuck".

There is still a **24-hour backstop**. If it expires with leads in flight the run
closes as `gave_up_waiting` — **a distinct outcome, not a finish.** Two fields on
the results summary say which happened:

| `settle_outcome` | Means |
|---|---|
| `no_wait_needed` | there was never any outstanding enrichment to wait for |
| `all_leads_terminal` | every lead reached a terminal state — the ordinary finish |
| `gave_up_waiting` | the 24-hour backstop fired. **Report this as a partial outcome** |

`leads_outstanding` carries the count the predicate saw (`null` where it was never
measured).

⚠️ **Zero outstanding work is a legitimate IMMEDIATE finish.** A run with every
enrichment stage disabled produces no per-lead jobs and completes in ~90 s with
`settle_outcome: no_wait_needed`. That is correct by construction — reading it as
a failure is a known bug that has been shipped twice and fixed twice.

⚠️ **Poll the PUBLIC `job_id`.** It is not the same value as the internal record
id. If you send the internal one you get a `404` that names the id you should have
used (`error.code: INTERNAL_JOB_ID_SUPPLIED`, `error.public_job_id`) — but only
for a job this tenant owns; another tenant's id returns a bare `404`.

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

✅ **This works for bulk runs as of 2026-08-25, and it did not before.** Until then the
carrier row that represents a bulk lead was inserted already-completed, so the callback
that writes a `results` row never fired, so the CRM sync worker had nothing to claim and
**no bulk lead ever reached the normalized corpus.** The carrier now writes its own
`results` row, and a bulk lead lands in `businesses` like any campaign lead.

🔴 **The campaign id is the bulk job id with its DASHES REMOVED.** This is the whole
trick, and getting it wrong is silent — a wrong value returns `count: 0`, exactly like a
value with no rows:

```
  bulk_job_id  (as the submit response returns it)   2cd290e9-897f-4ebe-9691-0231155e0915
  campaign_id  (what IDAP stores and filters on)     bulk_2cd290e9897f4ebe96910231155e0915
```

```bash
BULK_ID=2cd290e9-897f-4ebe-9691-0231155e0915
curl "https://spideriq.ai/api/v1/idap/businesses?campaign_id=bulk_${BULK_ID//-/}&include=emails,phones,domains,pins" \
  -H "Authorization: Bearer $SPIDERIQ_PAT"
```

Measured 2026-08-25 with a control, because "0 rows" and "wrong id" are the same
response and only a control tells them apart:

```
  A  campaign_id=bulk_2cd290e9897f4ebe96910231155e0915      count 3   <- undashed, correct
  B  campaign_id=bulk_2cd290e9-897f-4ebe-9691-0231155e0915  count 0   <- dashed
  C  campaign_id=bulk_zzzznotreal                           count 0   <- control
```

**B and C are indistinguishable.** If you get `count: 0`, check the dashes before
concluding the run produced nothing.

✅ **Past runs are in the corpus too.** Bulk runs submitted before 2026-08-25 were
backfilled on 2026-08-25 — every carrier, all synced — so this filter reads an old run
like any other. 🔴 **A `count: 0` on an old run is therefore NOT expected any more.**
Check the dashes on the `campaign_id` before concluding the run produced nothing: a
wrong id and an empty run give the same answer (controls A/B/C above).

Steps 2 + 3 still work on any run regardless, because they read the job results
directly rather than the corpus.

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
