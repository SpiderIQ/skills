# Run Social Media Enrichment for one business

Recover a missing email / phone / real website / socials for ONE business from
its public social handles, then read the result. Steps / Gotchas / Verify.

## Steps

### 1. Gather the business's social handles

You need at least ONE of: a social handle (facebook / instagram / linkedin /
twitter / tiktok) or a single social-only `website` (linktr.ee / facebook /
instagram URL). These usually come from a prior
`scrape-website-extract-leads` result or a Maps listing that had social links
but no email.

Pass a stable `place_id` (the business's Google place_id) whenever you have one —
it is the exactly-once recovery key (see Gotchas).

### 2. Submit the job

CLI:

```bash
spideriq social enrich \
  --facebook https://facebook.com/joesplumbing \
  --instagram joesplumbing \
  --place-id ChIJ0x1a2b3c4d5e6f \
  --business-name "Joe's Plumbing" \
  --country US
# → Job ID: 1764b3b3-a184-4177-96cf-97cd6ae46e85   Status: queued
```

MCP (`submit_social_enrichment`) — pass the handles as individual fields or as a
`social_media` map; they are merged:

```json
{
  "facebook": "https://facebook.com/joesplumbing",
  "instagram": "joesplumbing",
  "place_id": "ChIJ0x1a2b3c4d5e6f",
  "business_name": "Joe's Plumbing",
  "country_code": "US"
}
```

Raw HTTP (PAT) — the payload nests under `payload`:

```bash
curl -X POST "https://spideriq.ai/api/v1/jobs/spiderSocial/submit" \
  -H "Authorization: Bearer $SPIDERIQ_PAT" \
  -H "Content-Type: application/json" \
  -d '{
        "payload": {
          "social_media": {"facebook": "https://facebook.com/joesplumbing", "instagram": "joesplumbing"},
          "place_id": "ChIJ0x1a2b3c4d5e6f",
          "business_name": "Joe'\''s Plumbing",
          "country_code": "US"
        }
      }'
# → 201 { "job_id": "1764b3b3-…", "status": "queued" }
```

### 3. Poll for the result

The recovery runs in a worker seconds after the 201. Poll status, then read
results (add `?format=yaml` for ~40-76% fewer tokens):

```bash
spideriq social results 1764b3b3-a184-4177-96cf-97cd6ae46e85 --format yaml
```

```bash
curl -s "https://spideriq.ai/api/v1/jobs/1764b3b3-…/results?format=yaml" \
  -H "Authorization: Bearer $SPIDERIQ_PAT"
```

### 4. Verify a recovered email before outreach

If a `email` came back, hand it to `verify-email-deliverability` before it enters
an outreach sequence — recovery finds the address, verification confirms it's
safe to send to.

## Gotchas

- **WRONG:** reporting "recovered cs@joesplumbing.com" straight off the submit's
  201. **RIGHT:** the 201 is `{job_id, status:queued}` only — the recovered
  contact does not exist yet. Poll `getJobResults` until the job is terminal.
- **WRONG:** re-running the same business without a `place_id` "to be sure."
  **RIGHT:** there is no idempotency key — a second submit is charged again. Pass
  the stable `place_id`; the service uses it as the exactly-once recovery key.
- **WRONG:** submitting with no handle and no website, expecting an error.
  **RIGHT:** it self-skips `no_social_handle` (a completed result, not an error).
  Provide at least one handle or a website.
- **WRONG:** treating `status:skipped, reason:has_email` as a failure and
  retrying. **RIGHT:** that's the healthy "already had an email" outcome — no
  credit spent; move on.
- **WRONG:** looping this over hundreds of businesses one call at a time.
  **RIGHT:** for bulk, enable the `workflow.social_media_enrichment` stage on a
  `lead-search` campaign (`campaign-toggle.md`).

## Verify

- The submit returns HTTP 201 with a `job_id`.
- `getJobResults` eventually returns `status: "recovered"` (with
  `recovered_fields` non-empty) OR `status: "skipped"` with a `reason`.
- On a recovery, `recovered_fields` names exactly what was found and
  `credits_spent` is > 0; on a skip, no credit is spent.
