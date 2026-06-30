# Diagnose why an outreach mailbox isn't delivering

The symptom usually arrives as a Smartlead error — `domain_does_not_exist`,
`553 Relaying disallowed`, `5.4.4 NXDOMAIN` — or "the inbox looks stale / no new
replies." **Nine times out of ten it is NOT SpiderMail and NOT Smartlead** — it's
the domain's DNS or its Zoho state. Your job is to localize the fault to the
right *plane* before touching anything; fixing the wrong plane wastes hours.

Prereq: a `connection_id` — see [connect-and-inspect.md](connect-and-inspect.md).

## The four planes (localize first)

| Symptom | Plane | Who fixes it |
|---|---|---|
| Inbox returns rows but no *new* mail; mailbox looks idle | **SpiderMail** — mailbox `is_active=false` is never polled | you (set active) |
| `domain_does_not_exist` / NXDOMAIN / `SERVFAIL`; domain won't resolve | **DNS** — registrar NS or Cloudflare zone | operator (registrar/CF) |
| `553 Relaying disallowed / Invalid Domain`; sends rejected though DNS is fine | **Zoho** — domain not active-for-sending / missing DKIM | operator (Zoho + CF) |
| Warmup paused (INACTIVE) or low reputation, but DNS+Zoho are healthy | **Smartlead** — warmup auto-paused | operator (re-enable) |

## Steps — diagnose cheapest-first

1. **Is the mailbox active in SpiderMail?** An `is_active=false` mailbox is
   **never IMAP-polled**, so `/mail/inbox` serves only the last-polled snapshot —
   it *looks* stale but isn't bouncing. Fix it yourself: `PATCH /mail/mailboxes/{email} {"is_active":true}`
   (mail slice tool `update_mailbox`). No provider call needed.

2. **Does the domain resolve?** `dig @1.1.1.1 <domain> NS` and `… MX`. `SERVFAIL`
   / empty NS = the DNS plane is broken (most common: a Cloudflare zone was
   re-created and got a **new** nameserver pair the registrar still isn't pointing
   at). This is an **operator** fix at the registrar — report it precisely, don't
   try to "fix" it in Smartlead.

3. **Check the Zoho domain state.** `email_list_mailboxes({ connection_id })`
   shows per-mailbox `imap_enabled` / `registered`. For domain-level state
   (verification, DKIM, MX) the maintainer reads `GET /api/organization/domains`.
   ⚠️ **Zoho's `mxstatus:expired` / `isExpired` / `spfstatus:false` flags are
   STALE** — they read identically on a perfectly healthy domain. Do NOT conclude
   "expired = broken." Trust a real `dig` + a login probe instead.

4. **Probe the actual login.** `email_health_check({ connection_id, email, password })`
   does a REAL IMAP+SMTP login *with a password* (without one it's only a
   reachability probe — can falsely say "ok"). A green login + a resolving domain
   means the mailbox itself is fine and any Smartlead error is **historical**.

## What you can fix vs. what you escalate

- **You (existing tools):** mailbox `is_active` (mail `update_mailbox`),
  IMAP-off → [audit-and-reenable-imap.md](audit-and-reenable-imap.md)
  (`email_enable_imap`), missing registration → re-register.
- **Escalate to an operator (no MCP tool yet — give them the precise diagnosis):**
  registrar **NS repoint** (Netim), **Cloudflare** zone/record changes, publishing
  a domain's **per-domain DKIM + Zoho verify** record, and **Smartlead warmup
  re-enable**. The maintainer runbook with exact commands is SpiderMail
  `LEARNINGS.md §24–26`.

## WRONG → RIGHT

```
# WRONG — a Smartlead warmup bounce, so thrash on Smartlead / re-provision the mailbox
"warmup says domain_does_not_exist" → disable/re-add the Smartlead sender → still broken
```

```
# RIGHT — localize the plane first
dig @1.1.1.1 <domain> NS        # SERVFAIL → it's DNS, not Smartlead
# → report: "registrar NS for <domain> doesn't match its Cloudflare zone; needs repoint"
# the mailbox + Smartlead are fine; warmup recovers itself once the domain resolves
```

## Gotchas

- **Smartlead errors are often HISTORICAL.** Smartlead surfaces the *last* error,
  not a live one — `warmup_details.blocked_reason` keeps the old text (with its
  original date) until the next successful cycle. Check the *date* and the live
  `status`, not the message.
- **`is_active=false` ≠ broken.** It just means "not polled." Different fix
  (activate) from a domain failure (DNS/Zoho).
- **DKIM + verify records are per-domain** and can't be copied between domains —
  they come from the Zoho domains API.
- **Don't re-provision a mailbox to fix a domain problem.** The mailbox is almost
  always fine; the domain is the fault.

## Verify

- Domain: `dig @1.1.1.1 <domain> MX` returns the Zoho MX (`mx/mx2/mx3.zoho.eu`).
- Mailbox: `email_health_check(… , password)` → `imap_ok: true`, `smtp_ok: true`.
- Smartlead (if warmup was re-enabled by an operator): the sender's `status`
  flips to `ACTIVE`; the stale `blocked_reason` clears after the next cycle.
