# "completed" is a claim about the job row, not about the work

**Starting point, not ground truth — verify against current code.**

## The surprise

The first live bulk wave looked like a clean pass. The whole bulk machine worked:
submit → poll → fetch → parse → dedup → fan-out, three leads through, 200s
everywhere, records in the response with the right shape.

None of the pipeline stages had run. The WindMill flow's first module had
returned 401, and the flow died there — but `jobs.status` said `completed`, the
results endpoint returned a full body, and every customer-facing surface agreed
the run had succeeded.

## Why it reads as success

The job row and the flow are two different things, and only the job row is on the
customer path:

```
customer sees:   GET /jobs/{id}/status  → completed        ← the job ROW
                 GET /jobs/{id}/results → 200, full record  ← the seed, echoed
actually:        WindMill flow module a → 401, flow dead    ← nobody asked
```

The record in the response was the **purchased seed**, faithfully echoed. It has
the right field names and the right business, so nothing about it looks wrong.

This is **not** a bulk defect. The `failure_module` payload is byte-identical
between the bulk flow and the live `campaign_maps_site_verify_vayapin` flow, so
the live lead chain reports failures the same way today.

## What to assert instead

Ask for evidence the seed **could not** contain:

- **Verified emails.** Contact enrichment is never requested from the provider
  (`contact_enrichment=false`), so an email in the output can only have come from
  SpiderSite, and a verified one only from SpiderVerify. Their presence proves
  the chain ran.
- **`campaign_workflow_jobs > 0`** for the fan-out campaign. Zero is the signal
  that separated the failed run from the good one.
- **Per-stage outputs**, not the parent status.

The re-run passed on exactly this basis: `contact_enrichment=false` in the
provider digest, and five emails found / two verified in the output.

## What to do

- **Never report "the pipeline ran" from a 200 alone.** Say what stage evidence
  you actually saw.
- When a bulk run returns records but no emails/phones at all, treat it as
  *suspicious*, not as a thin purchase — check the fan-out campaign before
  telling the user to buy more.
- If you are verifying a run for someone, cross-check the flow, not the job.
