# Pace your submissions — ~10 jobs/min per VPS

**Starting point, not ground truth — verify against current code.**

## The surprise

The recommended way to run a batch of Maps searches is to loop the single
endpoint. But the submit route is **rate-limited to ~10 jobs/min per VPS**. A
naive `for` loop firing 50 submits back-to-back will start getting **429** part
way through.

This is **not** Google's ban detection (that's a separate, downstream cooldown on
the worker — see `2026-05-26-ban-cooldowns-and-timing`). This is SpiderIQ's own
submission throttle on the API.

## What to do

- **Pace the loop.** ~6–7 seconds between submits keeps you under ~10/min. (Maps
  jobs take 30–90s each to *run* anyway, so spacing submissions costs you nothing
  in wall-clock.)
- **Honor the headers.** The submit responses carry `X-RateLimit-Limit`,
  `X-RateLimit-Remaining`, and `X-RateLimit-Reset` (a Unix timestamp). On a 429,
  sleep until `X-RateLimit-Reset` rather than retrying blindly.
- **Mind the queue cap.** The Maps queue holds at most **10,000** jobs. You're
  unlikely to hit it from one client, but a huge fan-out plus existing fleet load
  can — size very large batches accordingly.

## Rule of thumb

Submissions are cheap to *create* but throttled. Space them out; don't tight-loop.
A batch of N queries should drip in over ~`N/10` minutes, not all at once.
