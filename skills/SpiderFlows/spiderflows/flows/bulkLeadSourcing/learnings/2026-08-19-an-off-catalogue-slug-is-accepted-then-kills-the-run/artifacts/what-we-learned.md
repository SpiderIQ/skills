# A 202 from a Sortlist submit does not mean the slugs were real

**Starting point, not ground truth — verify against current code.**

## The surprise

The bulk submit endpoint validates a lot before it answers. It refuses an
unknown provider, a provider/kind mismatch, an ineligible downstream stage, a
run over the record ceiling — each with a specific `422` naming the field.

So a `202` reads like "the buy order is well-formed".

For Sortlist, it isn't. Catalogue membership is not checked there.

```
POST /bulk-lead-sourcing/submit
  "provider": "sortlist",
  "queries": ["not-a-real-sortlist-service"]

  →  202  { "bulk_job_id": "…", "job_id": "78cfd334-…", "status": "pending",
            "estimated_records": 1,
            "message": "Bulk lead sourcing run accepted." }

GET /jobs/78cfd334-…/status          (~5 seconds later)

  →  { "status": "failed",
       "error_message": "ValidationError: 1 validation error for SortlistSelect
                         Value error, service 'not-a-real-sortlist-service'
                         is not in Sortlist's catalogue" }
```

## Why it lands there

Membership lives in `SortlistSelect`, which the **worker** builds when it picks
the manifest up. `prepare_submission` never constructs one — it validates the
provider-neutral buy order (provider, source_kind, stage eligibility, ceilings)
and writes the manifest. The slug is opaque to it.

That split is defensible: the catalogue is a property of one adapter, and the
submit path is deliberately provider-neutral. It is only a trap because the
`202` is indistinguishable from a good one.

## What it costs

Nothing, in money. The failure is upstream of everything expensive:

```
provider contacted    no
records parsed        none
leads fanned out      none
downstream stages     never reached
```

You get one `failed` job and a clear `error_message`. `POST /jobs/{id}/cancel`
returns 404 — by the time you look, it is already terminal.

## What to do

- **Pick slugs from the vocabulary. Never infer one from the user's wording.**
  "SEO" happens to be `seo`; "real estate" is *not* an industry slug at all.
- Remember services and industries share the one `queries` array and several
  slugs live on **both** axes — `branding`, `content-marketing`, `design`. An
  industry needs its `i/` prefix or you have silently asked for the service.
- **Do not report a Sortlist run as started on the strength of the 202.** Poll
  `GET /jobs/{job_id}/status` once before telling the user it is underway; a bad
  slug surfaces within seconds.
- This is the bulk flow's existing "a completed flow can still have failed"
  lesson pointing the other way: there, success was overstated at the end; here,
  it is overstated at the start.
