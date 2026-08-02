# Leave `from_email` / `hello_name` empty — the worker's identity is warmed

**Starting point, not ground truth — verify against current code.**

## The temptation

The payload exposes `from_email` (SMTP MAIL FROM) and `hello_name` (EHLO/HELO
hostname). It's tempting to set them to "look like" the sender, or to a client's
own domain. **Don't** — unless you genuinely run warmed sending infrastructure.

## Why the defaults win

The worker rotates across **50 pre-warmed sending identities**, spread over 10
hosts. Each identity sits on an IP whose **reverse-DNS (PTR) record matches its
EHLO hostname**. That match is the single most important factor in whether a
receiving mail server trusts the connection:

- **PTR ≠ EHLO → >50% rejection** from Gmail / Outlook and other major servers.
  The rejections come back to you as `unknown` / `risky` — so a "helpful"
  override silently *destroys* your accuracy.
- A fresh `from_email` has **zero sender reputation**. New identities need
  **2–4 weeks of warmup** before mail servers stop greylisting them. Point the
  probe at an un-warmed address and you get greylists and timeouts.
- Rotating across many identities also makes the verification pattern
  (CONNECT→EHLO→MAIL FROM→RCPT TO→QUIT, no DATA) less detectable; pinning one
  custom `from_email` makes the probing obvious and invites rate-limiting.

When `from_email` / `hello_name` are **empty or omitted**, the worker uses its
rotated, warmed, PTR-matched identity. That is the right default for essentially
every client call.

## When overriding is legitimate

Only if you operate your own warmed sending infrastructure — and then set them as
a **matched pair**: `hello_name` must be a hostname whose PTR resolves back to the
IP the probe egresses from, and `from_email` must be on a domain with sane SPF and
weeks of warmup. If you can't guarantee the PTR match, leave both empty.

## Rule of thumb

Treat `from_email` / `hello_name` as expert-only knobs. The honest answer to
"should I set these?" is almost always **no** — the empty default is the warmed,
reputation-protected path, and overriding it makes results *worse*, not better.
