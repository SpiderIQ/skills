# A slow or short run is usually throttling, not failure

**Starting point, not ground truth — verify against current code.**

## The surprise

Maps Search drives a real anti-detect browser against Google Maps, and Google
pushes back. The worker has **tiered ban-detection cooldowns** — when it sees a
block signal it waits before continuing:

| Signal | Threat level | Cooldown |
|---|---|---|
| Consent wall | LOW | 0s |
| reCAPTCHA iframe | MEDIUM | 30s |
| CAPTCHA form / "unusual traffic" | HIGH | 120s |
| Error page (403 / 429 / 503) | CRITICAL | 300s |

CAPTCHAs are **auto-solved** (2Captcha, ~$0.003/solve) when configured. So a run
that takes a few minutes, or comes back with fewer than `max_results` businesses,
is usually the worker waiting out a cooldown — **not a failure to fix.**

## Two consequences for how you drive it

1. **Set the user's timing expectation.** "This usually takes 30–90s but can take
   a few minutes if Google is throttling." Don't present a 2-minute run as stuck.
2. **Never tight-loop on status.** Polling every second doesn't make the worker
   go faster — the worker is *deliberately* idle during a cooldown. Poll every
   3–5s, or use the SSE stream and react to `job.completed`.

## Partial results are kept

Extracted businesses are persisted incrementally, so if a run is cut short by a
hard cooldown you still get what was scraped rather than nothing. A short list is
a partial success, not an empty failure — check `results_count` and, for a quick
verdict, run [`scripts/verify-maps-complete.sh`](../../../scripts/verify-maps-complete.sh).

## Distinguish from the *other* limit

This is Google's downstream throttle on the **worker**. There's a separate
SpiderIQ **submission** rate limit (~10 jobs/min per VPS) on the API — see
`2026-05-26-rate-limit-and-queue`. Different mechanisms, both worth knowing:
one paces how fast you *submit*, this one explains why a *running* job is slow.
