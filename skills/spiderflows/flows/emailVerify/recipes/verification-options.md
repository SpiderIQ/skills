# Reference: every payload option (the complete request contract)

emailVerify is a **single-stage** flow — no per-stage `config` blocks like the
multi-service chains. The whole verification is tuned through fields on the
request `payload`. This is the **complete** contract: every field, its default,
its bounds, and how it actually behaves at the worker. **Read this before
composing any non-default request** — several options are footguns.

Body shape (the endpoint wraps everything in `payload`, with `priority` as a
sibling):

```json
{
  "payload": {
    "email": "jane@acme.com",          // single  — OR —
    "emails": ["a@x.com", "b@y.com"],  // batch (≤100); provide EXACTLY one of email/emails

    "check_gravatar": false,
    "check_dnsbl": false,
    "smtp_timeout_secs": 45,
    "from_email": null,
    "hello_name": null,
    "fuzziq_enabled": null,
    "fuzziq_unique_only": null,
    "test": false
  },
  "priority": 0
}
```

Authority: `SpiderVerifyJobPayload` (`app/schemas/job.py:65-163`) for validation,
`workers/SpiderVerify/{worker.py,verification_engine.py}` for runtime behavior.

## The address — `email` xor `emails` (required)

| Field | Bounds | Notes |
|---|---|---|
| `email` | 3–320 chars | single mode |
| `emails` | 1–100 items | batch mode |

- **Exactly one.** Both set → `422` ("provide either … not both"); neither → `422`
  ("Either 'email' … or 'emails' … must be provided").
- **Batch hard-caps at 100.** `emails` with >100 entries → `422`. A list of 250 is
  three submissions; track each `job_id`.
- The core SMTP probe (CONNECT → EHLO → MAIL FROM → RCPT TO → QUIT, never DATA)
  **always** runs and yields `status`, `score`, the `flags`, and `domain`. The
  options below add *extra* checks or tune *how* the probe runs.

## Extra checks (opt-in — default OFF on the API)

| Field | Default | What it adds | Cost |
|---|---|---|---|
| `check_gravatar` | `false` | `gravatar_url` (+ `has_gravatar`); always emitted when set, `null` = "checked, none" | cheap HTTP hash lookup |
| `check_dnsbl` | `false` | the `dnsbl` block — probes 4 public blacklists (Spamhaus / SpamCop / Barracuda / SORBS) for the domain's MX IPs, returns `spam_trap_risk` 0–100 + `blacklists_hit` | a few DNS lookups |

> **API defaults are `false`.** You must pass `true` to get these. (The dashboard
> *form* `app/flows/emailVerify.yaml` defaults them on — that is a different
> surface. This recipe is the raw `/jobs/spiderVerify/submit` API, whose Pydantic
> model defaults them off. Don't assume DNSBL/gravatar ran unless you set them.)

## Tuning the SMTP handshake

| Field | Default | Bounds | Notes |
|---|---|---|---|
| `smtp_timeout_secs` | `45` | 10–120 | per-mailbox SMTP timeout. **Caveat:** the worker's HTTP call to its verification backend has a **60s hard ceiling**, so values much above ~55 don't fully apply — a slow server times the backend call out first and the email returns `unknown`. Lower values finish faster but turn slow-but-real servers into `unknown`. **The 45s default is the sweet spot — leave it unless you have a specific reason.** |
| `from_email` | rotated identity | valid email | overrides the SMTP MAIL FROM. **Empty/omitted = the worker's warmed, rotated identity (STRONGLY preferred).** |
| `hello_name` | worker domain | hostname | overrides the EHLO/HELO hostname. **Empty/omitted = the worker's configured domain whose reverse-DNS (PTR) matches.** |

### ⚠️ Do not override `from_email` / `hello_name` casually

The worker rotates across 50 pre-warmed sending identities, each on an IP whose
**PTR record matches its EHLO hostname**. That matching is the single most
important factor in not getting rejected — a mismatched `hello_name` causes
**>50% rejection** from Gmail/Outlook, which surfaces to you as inflated
`unknown` / `risky` rates and *worse* accuracy. A fresh, un-warmed `from_email`
has zero sender reputation and gets greylisted or blocked. **Leave both empty**
unless you operate your own warmed infrastructure with matching PTR — in which
case set them as a matched pair. See the `from-email-hello-name-deliverability`
learning.

## Dedup (quota saver) — FuzzIQ

| Field | Default | Notes |
|---|---|---|
| `fuzziq_enabled` | unset → off on this path | When `true`, addresses already verified for your tenant are **skipped** (not re-probed, not billed) and counted in `summary.fuzziq_skipped`. A single already-known email comes back `status: skipped` (`reason: already_verified`); an all-known batch comes back `results: []` with `summary.skipped`. This is the dedup **flag** on the verify request — **NOT** a separate dedupe call. |
| `fuzziq_unique_only` | unset | return only unique records (drop duplicate addresses from the response). |

Set `fuzziq_enabled: true` for recurring hygiene over the same lists — it stops
you paying twice for the same address. Leave it off (the default behavior on the
standalone job path) to force a fresh probe of every address.

## Submission knobs

| Field | Default | Bounds | Notes |
|---|---|---|---|
| `priority` | `0` | 0–10 | **sibling of `payload`**, not inside it. Higher is processed first. |
| `test` | `false` | — | routes to the test queue (local/dev workers only). Don't set in production. |

## Rule of thumb

- **Plain list hygiene:** `{"payload": {"emails": [...]}}` — the probe + MX +
  flags are always there; add nothing.
- **Spam-trap risk matters:** add `check_dnsbl: true`.
- **Want a human-exists signal:** add `check_gravatar: true`.
- **Recurring lists:** add `fuzziq_enabled: true`.
- **Timeout / from_email / hello_name:** leave them at defaults unless you have a
  specific, deliverability-aware reason — the defaults protect accuracy.
