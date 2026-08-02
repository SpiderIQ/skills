# Poll status + read the published release

After `submitPressRelease` returns a `job_id`, the release moves through the wire
asynchronously. Two reads:

- `getJobStatus` → `GET /api/v1/jobs/{job_id}/status` — lifecycle state.
- `getJobResults` → `GET /api/v1/jobs/{job_id}/results` — the published URL + wire report.

## Steps

1. **Poll status** (no faster than every 3-5 s):

   ```bash
   curl -s "https://spideriq.ai/api/v1/jobs/$JOB_ID/status?format=yaml" \
     -H "Authorization: Bearer $CLIENT_ID:$API_KEY:$API_SECRET"
   # status: queued | processing | completed | failed
   ```

2. **When `completed`, read results:**

   ```bash
   curl -s "https://spideriq.ai/api/v1/jobs/$JOB_ID/results?format=yaml" \
     -H "Authorization: Bearer $CLIENT_ID:$API_KEY:$API_SECRET"
   ```

3. **Read the fields you care about** from `data`:

   | Field | Meaning |
   |---|---|
   | `status` | `queued` \| `submitted` \| `published` \| `failed` |
   | `published_url` | Live URL of the published release (only once `published`) |
   | `wire_report_url` | The provider's distribution / wire report |
   | `provider_order_id` | The provider's order/submission id |
   | `title` | Release headline (echoed back) |
   | `scheduled_release_at` | Scheduled wire time, if you set one |
   | `published_at` | Actual publish time (ISO 8601) |
   | `error` | Failure reason — present only when `status: failed` |

## What a published result looks like

```yaml
success: true
job_id: "..."
type: spiderPR
status: completed
data:
  provider: prnow
  provider_order_id: "ord_..."
  status: published
  title: "Acme Corp launches AI-powered widget"
  published_url: "https://wire.example.com/acme-corp-launches-ai-powered-widget"
  wire_report_url: "https://wire.example.com/reports/ord_..."
  published_at: "2026-07-26T12:34:56Z"
```

## Gotchas

- **`published_url: null` while in flight is EXPECTED.** Before the wire goes
  live, `data.status` is `queued` / `submitted` and `published_url` is null.
  That is not an error — keep polling until `status: published` (or `failed`).
- **A failed job is not retryable in place.** `data.status: failed` carries the
  reason in `data.error`. Fix the copy and submit a NEW release (a new job_id);
  do not re-poll expecting it to recover.
- **Wholesale / margin figures are never in the result.** Only client-facing
  distribution data is returned — there is no cost field to surface.

## Verify

```bash
# Terminal state is one of completed/failed; a completed spiderPR job carries a
# published_url once the wire is live:
curl -s "https://spideriq.ai/api/v1/jobs/$JOB_ID/results?format=yaml" \
  -H "Authorization: Bearer $CLIENT_ID:$API_KEY:$API_SECRET" | grep -E "status:|published_url:"
```
