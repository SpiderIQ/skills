# Spin up N outreach mailboxes on a domain

The main recipe. Stand up a batch of cold-outreach mailboxes on one domain,
fully wired into SpiderMail, and (only if asked) warmed in Smartlead.

Prereq: a `connection_id` for the brand's provider org — see
[connect-and-inspect.md](connect-and-inspect.md).

## The load-bearing order

A mailbox is only usable when **all four** are done, in order:

```
provision → enable-imap → register (in SpiderMail) → health-check
```

`email_provision_and_link` does exactly those four in one call per mailbox — it
is the preferred path. The individual tools exist for repair/partial flows.

## Steps (one call per mailbox)

1. **Confirm there are free license seats.** Provisioning consumes a paid Zoho
   license seat. If the org is full, provision returns **409** with the verbatim
   provider reason (C1) — that means free/buy seats, not retry. A cheap way to
   gauge headroom is to inventory first:

   ```bash
   spideriq email mailboxes <connection_id>   # SLOW ~20s — see how many exist
   ```

2. **Provision + link each mailbox** (provision → IMAP → register → health):

   ```bash
   spideriq email provision-and-link \
     --connection-id <connection_id> \
     --local-part jane --domain outreach-example.com \
     --password 'S0meStr0ngPass!' \
     --display-name "Jane Doe"
   ```

   MCP: `email_provision_and_link({ connection_id, local_part: "jane", domain: "outreach-example.com", password: "…", display_name: "Jane Doe" })`.
   Loop over your N local parts. Each call is independent — one 409 doesn't
   poison the rest, so catch it per-mailbox and stop the loop when seats run out.

3. **Read each result.** The chain returns the provisioned email plus the
   register + health-check outcome (`imap_ok` / `smtp_ok`). A mailbox that
   provisioned but failed health-check usually means IMAP didn't propagate yet —
   re-run `email_health_check` with the password after a short wait, or
   `email_enable_imap` then re-check.

## Manual (when you need the steps apart)

If a flow half-completed, or you're wiring mailboxes that already exist:

```bash
# 1. provision (just creates it)
spideriq email provision --connection-id <id> --local-part jane --domain d.com --password '…'
# 2. enable IMAP — account_id + zuid from `email mailboxes`
spideriq email enable-imap --connection-id <id> \
  --targets '[{"account_id":"<acct>","zuid":"<zuid>","email":"jane@d.com"}]'
# 3. register in SpiderMail (idempotent)
spideriq email register --connection-id <id> --email jane@d.com --password '…' --display-name "Jane Doe"
# 4. health-check with the password (the trustworthy probe)
spideriq email health-check --connection-id <id> --email jane@d.com --password '…'
```

## (Opt-in) warm in Smartlead — ONLY if explicitly asked

This is a **separate, deliberate step** and is NEVER auto-chained after
provisioning (HARD-GATE / locked decision). Do it only when the user has asked to
"warm in Smartlead" / "add as a Smartlead sender" for that mailbox, and only
after it is **registered** in SpiderMail and the brand has an **active Smartlead
outreach connection** (otherwise 409).

```bash
spideriq email add-to-smartlead \
  --connection-id <connection_id> \
  --email jane@outreach-example.com \
  --max-email-per-day 50 \
  --warmup-enabled true
```

MCP: `email_add_to_smartlead({ connection_id, email, max_email_per_day: 50, warmup_enabled: true })`.
Defaults: `max_email_per_day` 50, `warmup_enabled` false. Omit
`smartlead_connection_id` to use the brand's active outreach connection.

## Gotchas

- **409 on provision = no free license seat (C1).** Not a transient error — do
  NOT retry. Surface the provider message; the operator frees/buys a seat.
- **Smartlead is never automatic.** `provision_and_link` deliberately stops
  before Smartlead. Adding a mailbox to live rotation is a different consent level.
- **`add_to_smartlead` 409s** if the mailbox isn't registered in SpiderMail or
  the brand has no active Smartlead outreach connection — register + confirm the
  outreach connection first.
- **`password` must be ≥8 chars** on provision / provision-and-link.
- **The mailbox list is slow** (~20s cold) — inventory once, don't poll.

## Verify

- `email_health_check({ connection_id, email, password })` → `imap_ok: true`,
  `smtp_ok: true` for each new mailbox (the real-login proof).
- `email_list_mailboxes({ connection_id })` shows each new mailbox annotated
  `imap_enabled: true`, `registered: true` (and `smartlead_sender: true` only for
  the ones you opted in).
- `email_audit({ connection_id })` shows the `provision` / `enable_imap` /
  `register` (and any `add_to_smartlead`) actions with `result: ok`.
