# Submit a press release for wire distribution

`submitPressRelease` → `POST /api/v1/jobs/spiderPR/submit`. Async: returns a
`job_id`, then you poll (see `read-results.md`).

## Steps

1. **Confirm the copy is client-approved.** Every submit is a paid, irreversible
   newswire distribution (SKILL.md HARD-GATE). Re-submitting sends a SECOND
   release — it is not a retry.

2. **Build the payload — release fields go inside `payload`.**

   ```json
   {
     "payload": {
       "title": "Acme Corp launches AI-powered widget",
       "body": "AUSTIN, TX — Acme Corp today announced the launch of its AI-powered widget, the first to ...",
       "summary": "Acme's new widget brings on-device AI to small businesses.",
       "category": "Technology",
       "tags": ["ai", "product-launch", "smb"],
       "contact": {
         "name": "Jane Doe",
         "email": "press@acme.com",
         "phone": "+1-555-123-4567"
       }
     },
     "priority": 5
   }
   ```

   - `title` (required, 1-300) and `body` (required, 1-50000, plain text or HTML)
     are the only mandatory fields.
   - `summary`, `category`, `tags` (≤25), `contact` (name/email/phone, all
     optional) are optional structured metadata.
   - `provider` defaults to `"prnow"` (the only provider today) — omit it.

3. **Submit.**

   ```bash
   curl -X POST "https://spideriq.ai/api/v1/jobs/spiderPR/submit" \
     -H "Authorization: Bearer $CLIENT_ID:$API_KEY:$API_SECRET" \
     -H "Content-Type: application/json" \
     -d '{"payload":{"title":"Acme Corp launches AI-powered widget","body":"AUSTIN, TX — Acme Corp today ..."},"priority":5}'
   # → 201 { "job_id": "...", "status": "queued", ... }
   ```

4. **Keep the `job_id`.** It is the ONLY handle to the release from here on — poll
   it (`read-results.md`) for the published URL.

## Scheduled / embargoed release

For an embargo, set `payload.scheduled_release_at` to an ISO-8601 time; omit it
for ASAP distribution:

```json
{ "payload": { "title": "...", "body": "...", "scheduled_release_at": "2026-08-01T09:00:00Z" } }
```

## Test mode

Set `payload.test: true` to route the job to the local test queue (no live wire
distribution). Use it to exercise the submit path without spending on a real
release.

## Gotchas

- **WRONG:** `{"title": "...", "body": "..."}` at the top level → **422**. The
  release fields live under `payload`. **RIGHT:** `{"payload": {"title": "...", "body": "..."}}`.
- **WRONG:** treating the 201 response's `job_id` as "published, here's the link."
  The submit is async — there is no URL yet. **RIGHT:** poll `getJobStatus`, then
  read `getJobResults.published_url`.
- **WRONG:** re-POSTing the same release because the first "looked stuck." That
  sends and bills a SECOND distribution. **RIGHT:** poll the first `job_id`;
  wire distribution takes minutes.
- **WRONG:** 25+ `tags` → validation error (`tags` caps at 25).

## Verify

```bash
# A well-formed submit returns 201 with a job_id and status "queued":
curl -s -o /dev/null -w "%{http_code}\n" -X POST \
  "https://spideriq.ai/api/v1/jobs/spiderPR/submit" \
  -H "Authorization: Bearer $CLIENT_ID:$API_KEY:$API_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"payload":{"title":"Test","body":"Test body","test":true}}'
# → 201  (401/403 = auth; 422 = payload shape — check you wrapped under `payload`)
```
