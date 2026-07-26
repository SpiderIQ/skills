# Submit is async, paid, and not idempotent

**Verify against current API behaviour before relying on this.**

## What bites

`submitPressRelease` (`POST /api/v1/jobs/spiderPR/submit`) is an **async job
submission**, not a synchronous "publish and return the link" call. The 201
response gives you a `job_id` and `status: "queued"` — nothing more. The release
is only rendered to wire-ready HTML and pushed to the distribution provider by a
back-end poll worker, seconds to minutes later. The live `published_url` and the
provider's `wire_report_url` appear **only** in `getJobResults`, and only once
`data.status` reaches `published`.

Three failure modes follow from this:

1. **"Here's your published link" off the 201** — there is no link yet. Surfacing
   one is a silent lie. Poll `getJobStatus`, then read `getJobResults`.

2. **Re-submitting is a second paid distribution, not a retry.** There is no
   idempotency key. If a submit "looks stuck," the release is almost certainly
   still in flight (wire distribution is slow). Poll the existing `job_id` — do
   **not** POST the release again, or the client is billed for two wires and two
   releases go public.

3. **A failed job does not recover by polling.** When `data.status` is `failed`,
   the reason is in `data.error`. That job is terminal. Fix the copy and submit a
   **new** release (a new `job_id`).

## Right shape

```
submitPressRelease  →  job_id (status: queued)
      │
      ▼  poll every 3-5 s
getJobStatus  →  queued | processing | completed | failed
      │  (completed)
      ▼
getJobResults →  data.status: published, published_url, wire_report_url
```

## Why it's built this way

The wire provider is an external, slow, paid service. Decoupling submission from
publication (via the `job_queue` + `prNow` poll worker) is what lets the client
fire-and-poll instead of holding a request open for minutes. The cost is that the
client agent must treat submit and publish as two distinct events — exactly the
same shape as an email send (`spidermail`), a maps scrape, or any other SpiderIQ
async job.
