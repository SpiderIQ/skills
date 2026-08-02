# `unknown` is a soft outcome — re-verify, don't discard

**Starting point, not ground truth — verify against current code.**

## The surprise

A list comes back with a chunk of `unknown` rows. The temptation is to treat them
like `invalid` and drop them. That throws away real addresses.

## What `unknown` actually means

`unknown` reflects the **probe**, not the **mailbox**. SpiderVerify simulates an
SMTP handshake; `unknown` is what you get when that handshake couldn't reach a
verdict:

- the receiving server was unreachable or timed out,
- the verifier's sending IP was rate-limited / throttled,
- the destination greylisted the connection (a deliberate "try again later"),
- port 25 was blocked end-to-end.

The address behind an `unknown` may be perfectly valid — you just didn't get a
clean answer this time.

## What to do

- **Bucket `unknown` separately** from `invalid`. Report it as "couldn't
  determine — re-verify later".
- **Re-submit `unknown` addresses** after a delay; greylisting and transient
  throttling usually clear on a later attempt.
- **Don't chase a lower `unknown` rate by cutting `smtp_timeout_secs`.** A lower
  timeout makes it *worse* — slow-but-real servers get cut off and return
  `unknown`. The 45s default is a deliberate balance.
- Check `sub_status` for the detail (`smtp_unreachable`, etc.) when you need to
  explain *why*.

## Rule of thumb

Four statuses, three meanings: `valid` = send, `invalid` = don't, `risky` = send
with caution — and `unknown` = **ask again later**. Never let `unknown` collapse
into `invalid`.
