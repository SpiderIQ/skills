# Verification is slow by design — budget minutes, never tight-loop

**Starting point, not ground truth — verify against current code.**

## The surprise

Email verification feels like it should be instant — it's "just a lookup". It
isn't. A single email takes **3–10 seconds**; a full list of 100 takes roughly
**5–8 minutes**.

## Why it's deliberately slow

Each verification is a live SMTP handshake against the receiving mail server.
SpiderVerify rate-limits to **~3 seconds between probes** (~20/minute per worker)
on purpose: probing faster makes the verifying IP look like a spammer, gets it
added to DNSBL blacklists, and **takes days to recover from**. The delay is the
single most important knob protecting verification accuracy — it is never reduced
below 3s.

## What to do

- **Set expectations up front.** Tell the user a single check is seconds and a
  list of 100 is several minutes — before you submit, not after they ask why it's
  hanging.
- **Poll no faster than every 3–5s**, or subscribe to the SSE stream. A tight
  loop burns your tokens and rate limit and does **not** make the workers go
  faster.
- **Prefer smaller, targeted lists.** Don't verify 100 speculative addresses when
  the user needs the 10 that matter.
- **Scale by submitting in parallel batches**, not by trying to make one job
  faster — throughput comes from more workers, not a shorter delay (which you
  can't set anyway).

## Rule of thumb

Treat emailVerify like a background job, not a synchronous call. Submit, tell the
user how long it'll take, poll gently or stream, then read results.
