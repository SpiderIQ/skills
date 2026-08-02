# Queued ≠ sent — a SpiderMail send is an async job

*Starting point, not ground truth — verify against current behaviour.*

## The surprise

Every email API an agent has seen — Resend, Postmark, SendGrid — returns a
**message id synchronously**: you POST, you get back "here is the id of the email
I just accepted/sent." SpiderMail does **not**. `sendEmail`
(`POST /jobs/spiderMail/submit`) enqueues a job on RabbitMQ and returns:

```json
{ "job_id": "job_…", "status": "queued" }
```

The actual SMTP send runs in the SpiderMail **worker** seconds later
(API → RabbitMQ → Worker → SMTP). A `201` means the job was **accepted**, not
that the email left the building.

## Why it matters

The worker can still **fail** the send after you got your 201 — SMTP auth error,
connect timeout, a recipient the server rejects. If you told the user "email
sent!" off the submit response, you lied. The contract is:

1. submit → `job_id`
2. poll `get_job_status` (≥3–5 s apart) until `completed` or `failed`
3. report delivery only on `completed`; surface the real error on `failed`

The worker propagates the real exception class + message verbatim
(`SMTPAuthenticationError`, `SMTPConnectTimeoutError`, …) — no generic "send
failed" placeholder — so a `failed` job tells you what actually broke.

## No idempotency key → retries double-send

There is **no idempotency-key** mechanism. Postmark has the same limitation and
explicitly tells integrators to build their own dedup. So:

- submit **once**;
- if you're unsure whether your first submit landed (network blip on your side),
  **check `list_jobs` first** — don't blindly re-submit, or you'll send the email
  twice.

## What "good" looks like (the loop)

```
submit(test=true during dev) → job_id
loop: get_job_status(job_id)  until completed|failed
completed → "Delivered."     failed → surface error.name + error.message
```

## See also

- `references/send-reply-forward.md` — the WRONG/RIGHT of the submit→poll loop.
- The dispatcher contract (`docs/services/fastapi/DISPATCHER-CONTRACT.md`) owns
  give-up/retry decisions — the worker just sends and heartbeats; it never
  self-cancels.
