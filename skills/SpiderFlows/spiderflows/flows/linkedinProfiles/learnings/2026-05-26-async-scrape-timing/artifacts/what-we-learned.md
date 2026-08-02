# profile and company take minutes; only search is instant

**Starting point, not ground truth — verify against current code.**

## The surprise

These three modes feel like "look up a thing", but two of them are **asynchronous
scrapes the worker polls to completion**, with no fixed deadline:

| Mode | Mechanism | Realistic time |
|---|---|---|
| `profile` | triggers a Bright Data dataset scrape → polls the snapshot ~1×/s | **20s – ~2 min** (longer for heavy profiles) |
| `company` | starts an Apify actor run → polls ~1×/2s | **minutes**, scales with `max_employees` × `profile_mode` |
| `search` | one Google-SERP call (60s timeout) | **seconds** |

The poll loops are `while True:` — they run until the data is ready or the
dispatcher reaps the job for exceeding its SLA. There is **no client-set timeout**.

## Why it matters

- **Set the user's expectation.** For profile/company say "this takes a few
  moments / a few minutes", not "instant". A 1,500-employee `full_email` company
  pull can run for many minutes.
- **Never tight-loop the status endpoint.** Polling every 200ms does not make Bright
  Data or Apify finish faster — it just burns your rate limit and tokens. Poll no
  faster than every **3–5 seconds**, or subscribe to the SSE stream and react to
  `job.completed`.
- **A long-running job that gets reaped** comes back with
  `revoked_by_dispatcher: true` in the payload — treat it as incomplete and
  resubmit (usually with a smaller `max_employees`).

## Rule of thumb

- profile / company → budget minutes, poll at 3–5s or use SSE.
- search → expect seconds.
- One job is one scrape; don't fire a second identical one while the first is still
  running.
