# A "valid" email can score low — and verification is slow by design

**Starting point, not ground truth — verify against current code.**

## The surprise

SpiderVerify gives each email both a `status` (`valid`/`risky`/`invalid`/`unknown`)
and a `score` (0–100). Users expect a `valid` email to score near 100. It often
doesn't — and that's correct.

## How the score works

It starts at 50 and adds/subtracts:

- Positive: valid syntax (+10), MX found (+10), SMTP connectable (+10),
  deliverable (+20).
- Negative: catch-all (−15), disposable (−30), role account (−10), disabled (−50),
  full inbox (−20).

So:
- A perfect address on a normal domain → ~100.
- A valid, deliverable address on a **catch-all** domain → ~60s (the −15, plus
  catch-all blocks the +20 "deliverable" confidence).
- A valid **disposable** address → can be ~30.
- A `role` account like `info@` / `sales@` → −10 even when perfectly valid.

`status: valid` + a score of 62 is **not a contradiction** — the email resolves,
but its domain is catch-all so confidence is lower. Explain the score from the
quality flags (`is_catch_all`, `is_disposable`, `is_role_account`) rather than
treating a low score as "the email is bad".

## Verification is deliberately slow

SMTP verification is rate-limited (~a few seconds per email) to protect sender
reputation — going faster gets the verifying IPs blacklisted. A company with many
extracted emails therefore adds real wall-clock time. If the user only needs the
top few contacts, cap `spiderverify.max_emails` rather than verifying everything.

## Rule of thumb

- Surface `status` AND the relevant quality flag, not just the number.
- Don't tell the user a `valid` email is "low quality" — tell them *why*
  (catch-all / role / disposable).
- Budget time for verification on email-heavy companies; cap `max_emails` to speed
  it up.
