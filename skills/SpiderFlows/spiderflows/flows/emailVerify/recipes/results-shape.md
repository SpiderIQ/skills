# Reference: the complete shape of a verified email record

Everything one email carries after verification — every field, every enumerated
value, and exactly how each is derived — so you can read a result back and
explain it without guessing. This is one entry in `results[]` from
`/jobs/{job_id}/results` (single = one entry, batch = one per *verified* email).

Grounded in the worker: `workers/SpiderVerify/verification_engine.py`
(`_transform_result`, `_determine_sub_status`, `_calculate_score`,
`_detect_provider`, `check_dnsbl`) and `workers/SpiderVerify/worker.py`
(`process_job` — single vs bulk, FuzzIQ skip). Verify against current code.

## The result envelope

```yaml
total: 1                     # emails actually verified (AFTER FuzzIQ dedup)
summary:                     # authoritative counts — read these, don't recount
  valid: 1
  invalid: 0
  risky: 0
  unknown: 0
  fuzziq_skipped: 0          # present on bulk; emails removed by dedup (NOT in results[])
billable_count: 1            # what you paid for (= verified count, after dedup)
results:
  - email: jane@acme.com
    status: valid            # valid | invalid | risky | unknown | skipped
    sub_status: deliverable  # see the ordered table below
    quality: good            # good | risky | bad | unknown
    score: 95                # 0-100, exact formula below
    flags: { ...9 booleans... }
    domain: { name, mx_found, mx_records, smtp_provider }
    dnsbl: { spam_trap_risk, blacklists_hit, checked_at }   # only if check_dnsbl
    gravatar_url: https://...                               # only if check_gravatar (may be null)
    did_you_mean: null       # typo suggestion, only when the backend returns one
metadata: { total_time_seconds: 4.2, rate_limit_delay_seconds: 3.0 }
```

## `status` — the verdict (FIVE possible values)

The first four are the SMTP verdict (Reacher `is_reachable` → SpiderIQ via a fixed
map: `safe→valid`, `invalid→invalid`, `risky→risky`, `unknown→unknown`):

| `status` | Meaning | Send? |
|---|---|---|
| `valid` | mailbox confirmed deliverable at SMTP | yes |
| `invalid` | mailbox does not exist / disabled | no |
| `risky` | exists but flagged (catch-all, role, full inbox) | with caution |
| `unknown` | probe couldn't decide — SMTP blocked, timed out, rate-limited | **re-verify later, don't discard** |

The fifth only appears when FuzzIQ dedup recognized the address:

| `status` | Meaning |
|---|---|
| `skipped` | already verified for your tenant — FuzzIQ returned the cached verdict instead of re-probing (carries `reason: already_verified`). Not billed. |

> A bulk row that *errored mid-probe* comes back as `status: unknown` with
> `sub_status: "error: <message>"` and only two flags
> (`is_valid_syntax: true, is_deliverable: false`). Treat it like any other
> `unknown` — re-verify.

## `sub_status` — the reason detail (first match wins, in THIS order)

`_determine_sub_status` checks conditions top-down and returns the **first** that
matches — so a catch-all role account reads `catch_all`, not `role_account`:

| Order | `sub_status` | Set when |
|---|---|---|
| 1 | `catch_all` | domain accepts all addresses (`is_catch_all`) |
| 2 | `disposable` | Reacher flagged a disposable provider |
| 3 | `role_account` | generic address (`info@`, `sales@`, …) |
| 4 | `disabled` | the mailbox is disabled |
| 5 | `full_inbox` | the mailbox is full |
| 6 | `smtp_unreachable` | couldn't open an SMTP connection |
| 7 | `deliverable` | reachable = safe and none of the above |
| 8 | `mailbox_not_found` | reachable = invalid |
| — | `""` (empty) | none of the above (e.g. risky for an unclassified reason) |

## `quality` — the coarse grade

A direct map from `status`: `valid→good`, `invalid→bad`, `risky→risky`,
`unknown→unknown`. It carries no information beyond `status` — prefer `status` +
`flags` for any real decision.

## `score` — the 0-100 confidence (EXACT formula)

Base **50**, then:

| Factor | Δ |
|---|---|
| valid syntax | +10 |
| MX records found (`accepts_mail`) | +10 |
| SMTP connectable (`can_connect_smtp`) | +10 |
| deliverable | +20 |
| catch-all | −15 |
| disposable | −30 |
| role account | −10 |
| disabled | −50 |
| full inbox | −20 |

Clamped to 0–100. Worked examples:

- Perfect address on a normal domain: 50+10+10+10+20 = **100**.
- Valid, deliverable address on a **catch-all** domain: catch-all blocks the +20
  "deliverable" and subtracts 15 → ~**55–65**.
- Valid **disposable**: 50+10+10+10+20−30 = ~**70** (or lower if also catch-all).
- A `role` account otherwise perfect: 100−10 = **90**.
- Disabled mailbox: 50+10(syntax)+10(MX)+10(SMTP)−50 = **30** or less.

**`status: valid` + a mid score is not a contradiction** — explain it from the
flags, never as "the email is bad". See the `valid-can-score-low` learning.

## `flags` — nine booleans (how each is derived)

| Flag | True means | Source |
|---|---|---|
| `is_valid_syntax` | the address parses | Reacher `syntax` |
| `is_deliverable` | SMTP confirmed the mailbox accepts mail | Reacher `smtp` |
| `is_free_email` | free provider | **domain matched against a hardcoded list** (gmail, yahoo, hotmail, outlook, aol, icloud, mail.com, protonmail, zoho, yandex, gmx.*, web.de, live, msn) — a lookup, not an SMTP signal |
| `is_disposable` | temporary/throwaway provider | Reacher's check **OR** a hardcoded disposable-domain list. The fallback fires **even when SMTP is unreachable** — so `is_disposable: true` can appear on an `unknown` result |
| `is_role_account` | generic address (`info@`, `support@`, …) | Reacher `misc` |
| `is_catch_all` | the domain accepts *every* address | Reacher `smtp` — caps confidence (see gotchas) |
| `is_disabled` | the mailbox is suspended/disabled | Reacher `smtp` |
| `has_full_inbox` | the mailbox is full | Reacher `smtp` |
| `has_gravatar` | a Gravatar exists for the address hash | true iff `gravatar_url` is non-null (only meaningful with `check_gravatar`) |

## `domain`

| Field | Notes |
|---|---|
| `name` | the part after `@` (lowercased) |
| `mx_found` | the domain accepts mail (`accepts_mail`) |
| `mx_records` | MX hostnames (the worker repairs an occasional first-record TLD truncation, so these are reliable) |
| `smtp_provider` | detected from the MX hostnames: one of `google`, `Microsoft`, `Yahoo`, `Zoho`, `ProtonMail`, `iCloud`, `GoDaddy`, `Namecheap`, `Amazon SES`, `SendGrid`, `Mailgun`, or `Other` (null if no MX) |

## `dnsbl` (only when `check_dnsbl: true`)

```yaml
dnsbl:
  spam_trap_risk: 0          # 0-100 = hits / total_probes * 100
  blacklists_hit: []         # subset of the 4 zones probed
  checked_at: 2026-05-26T...Z
```

The worker resolves up to 3 MX hosts to IPs and probes 4 public zones —
**Spamhaus (`zen.spamhaus.org`), SpamCop (`bl.spamcop.net`), Barracuda
(`b.barracudacentral.org`), SORBS (`dnsbl.sorbs.net`)**. `spam_trap_risk` is the
fraction of (MX × zone) probes that hit, ×100. A non-empty `blacklists_hit` means
the *sending domain's mail servers* are listed — a deliverability/reputation
signal, not proof the address is a trap. On internal error the block returns
`spam_trap_risk: 0` plus an `error` field (so "0" can mean "clean" *or* "couldn't
check" — look for `error`).

## `gravatar_url` (only when `check_gravatar: true`)

Always **present** when the flag was set — `null` means "checked, none found"
(distinct from "not checked", where the field is absent). A non-null URL is a
weak "this is a real person who uses this address" signal.

## `did_you_mean`

Present only when the backend returns a typo suggestion (e.g.
`jane@acme.con` → `jane@acme.com`). Surface it to the user — it often explains an
`invalid` result and gives them the correction for free.

## Gotchas

- **`status` has five values, not four** — `skipped` (FuzzIQ duplicate) is normal
  on accounts with dedup on; it carries the cached verdict, not a fresh probe.
- **`sub_status` is first-match-wins** — a catch-all role account reads
  `catch_all`. Don't infer "not a role account" from `sub_status` alone; read the
  `flags`, which are independent booleans.
- **A catch-all domain caps confidence.** `is_catch_all: true` ⇒ the server
  accepts every address, so SMTP can't prove *this* mailbox exists → status tends
  to `risky`, score drops ~15, and the +20 deliverable bonus is withheld.
- **`is_disposable` can be true on an `unknown`** (hardcoded fallback), but
  `sub_status: disposable` only fires from Reacher's own check — so a disposable
  on a dead SMTP server shows `flags.is_disposable: true` with
  `sub_status: smtp_unreachable`. The flag is the reliable signal.
- **`spam_trap_risk: 0` is ambiguous** — clean *or* the check errored. Check for a
  `dnsbl.error` field before reporting "not blacklisted".
- **`is_free_email` / `is_disposable` are list lookups**, not live checks — a
  brand-new disposable domain not on the list won't be flagged. Don't promise
  exhaustive disposable detection.
