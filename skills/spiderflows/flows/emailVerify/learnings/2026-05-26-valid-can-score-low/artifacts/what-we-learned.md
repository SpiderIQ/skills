# A "valid" email can score low — and that's correct

**Starting point, not ground truth — verify against current code.**

## The surprise

Each result carries both a `status` (`valid`/`risky`/`invalid`/`unknown`) and a
`score` (0–100). Users expect a `valid` email to score near 100. It often
doesn't — and the lower number is right.

## How the score works

Base **50**, then add/subtract:

- Positive: valid syntax (+10), MX found (+10), SMTP connectable (+10),
  deliverable (+20).
- Negative: catch-all (−15), disposable (−30), role account (−10),
  disabled (−50), full inbox (−20).

So:
- A perfect address on a normal domain → ~95–100.
- A valid, deliverable address on a **catch-all** domain → ~60s (the −15, *and*
  catch-all blocks the +20 "deliverable" confidence — the server accepts every
  address, so it can't prove this mailbox specifically exists).
- A valid **disposable** address → can be ~30.
- A `role` account like `info@` / `sales@` → −10 even when perfectly valid.

`status: valid` + a score of 62 is **not a contradiction** — the email resolves,
but its domain is catch-all so confidence is lower.

## What to do

- Surface `status` AND the relevant quality flag (`is_catch_all`,
  `is_disposable`, `is_role_account`), not just the number.
- Don't tell the user a `valid` email is "low quality" — tell them *why*
  (catch-all / role / disposable).
- For a "safe to send" cut, filter `status == "valid"` AND `score >= 80`; for
  "deliverable at all", `status == "valid"` is enough.

## Rule of thumb

The score is a *confidence*, not a verdict. The verdict is `status`. A low score
on a `valid` email means "real, but lower certainty" — explain it from the flags.
