---
name: mail-admin
version: 0.1.0
description: >
  Provision and operate outreach mailboxes on a provider org (Zoho EU first) —
  the Email Admin control plane. Trigger on: "spin up N cold-outreach mailboxes
  on <domain>", "create mailboxes for a brand", "provision a mailbox", "enable
  IMAP on these mailboxes", "audit all mailboxes and re-enable IMAP where it's
  off", "rotate / reset passwords for a domain", "register a mailbox in
  SpiderMail", "health-check a mailbox (IMAP/SMTP login)", "connect a Zoho org",
  "add a mailbox to Smartlead as a sender", "read the email-admin audit log".
  This is the platform CONTROL plane (org-admin actions over a provider's API),
  super_admin / X-Admin-Key only — it is NOT how you read or send mail from a
  mailbox (that is SpiderMail / @spideriq/mail-skills), and NOT how you manage
  provider API keys / the vault (that is the integrations surface). Read it
  before touching any email_* tool — provisioning consumes paid license seats and
  mutates real provider orgs.
client: mail-admin
client_version: "0.1.0"
category: admin
triggers:
  - provision outreach mailboxes
  - spin up cold email mailboxes
  - create a mailbox on a domain
  - enable IMAP on mailboxes
  - audit mailboxes and re-enable IMAP
  - rotate mailbox passwords
  - register a mailbox in SpiderMail
  - health check a mailbox
  - connect a Zoho org
  - add a mailbox to Smartlead
  - read the email admin audit log
requires_auth: true
requires_brand: false
---

# Email Admin (provision + operate outreach mailboxes)

The **control plane** for outreach mailboxes: connect a provider org (Zoho EU),
provision mailboxes, enable IMAP, set passwords, register them into SpiderMail so
the data plane can poll/send, health-check them with a real login, and — as a
**separate, deliberate opt-in** — add a mailbox to the brand's Smartlead account
as an outreach sender. Every action runs against a real provider org and is
written to a god-mode audit log.

```
email_connect_provider     ─▶  attach a Zoho-EU org to a brand (vault token)         → connection_id
email_list_mailboxes       ─▶  live org inventory + SpiderIQ state (SLOW ~20s cold)
email_provision_mailbox    ─▶  create local_part@domain (consumes a LICENSE SEAT → 409 if full)
email_enable_imap (bulk)   ─▶  flip IMAP on N mailboxes; each target independent
email_register_in_spidermail ─▶ add to mail_mailboxes so SpiderMail can poll/send  (idempotent)
email_health_check         ─▶  REAL IMAP+SMTP login probe (only trustworthy with a password)
email_provision_and_link   ─▶  provision → enable-imap → register → health  (NO Smartlead)
email_add_to_smartlead     ─▶  OPT-IN ONLY — add a registered mailbox as a Smartlead sender
email_audit                ─▶  every connect/provision/enable/set-password/register/… action
```

> **AUTH:** every `email_*` call carries the platform admin key (`X-Admin-Key`,
> from `SPIDERIQ_ADMIN_API_KEY`) — **not** a client PAT. The endpoints accept
> EITHER that key OR a dashboard super_admin session; the key is what a headless
> agent uses. This is a **cross-tenant god-mode surface** — one super-admin
> acting over many brands' provider orgs. Never echo the key into logs or chat.

## The one mental model that prevents every mistake

**Two planes, one mailbox.** The *control* plane (this skill) talks to the
**provider's org API** — it creates the mailbox, toggles IMAP, sets the password.
The *data* plane (SpiderMail) talks to the **mailbox itself** over IMAP/SMTP — it
polls and sends. A mailbox you provision is **invisible to SpiderMail until you
`register` it**, and it can't be polled until **IMAP is enabled at the provider**.
So the load-bearing order is always **provision → enable-imap → register →
health-check**; `email_provision_and_link` does exactly those four in one call.
Smartlead is a *third* system bolted on after registration — never part of that
chain.

## Approach

- **Set up once per brand** — `email_connect_provider` attaches a Zoho-EU org
  (via an existing vault ref like `apiint:106`, or an inline OAuth bundle that
  gets stored in the vault first). One connection per brand-org; reuse its
  `connection_id` for everything else. → [references/connect-and-inspect.md](references/connect-and-inspect.md)
- **Spin up a fleet** — provision N mailboxes on a domain, enable IMAP, register
  each in SpiderMail, health-check. Prefer `email_provision_and_link` per mailbox
  (it runs the whole chain + a real login probe). → [references/provision-outreach-fleet.md](references/provision-outreach-fleet.md)
- **Repair a fleet** — list the org inventory (annotated with `imap_enabled`,
  `registered`, `smartlead_sender`), then bulk `email_enable_imap` on the ones
  that are off. The proven fleet-recovery path. → [references/audit-and-reenable-imap.md](references/audit-and-reenable-imap.md)
- **Diagnose deliverability** — a mailbox bounces in Smartlead
  (`domain_does_not_exist`, `553`, NXDOMAIN) or its inbox looks stale. Localize the
  fault to the right plane (SpiderMail `is_active` / DNS / Zoho / Smartlead) before
  touching anything — it's usually DNS, not Smartlead. → [references/diagnose-deliverability.md](references/diagnose-deliverability.md)
- **Rotate credentials** — reset the provider password for every mailbox on a
  domain and re-register so SpiderMail keeps the new password. → [references/rotate-passwords.md](references/rotate-passwords.md)
- **Warm in Smartlead (opt-in)** — only on explicit instruction, add a
  *registered* mailbox to the brand's Smartlead account as a sender. → [references/provision-outreach-fleet.md](references/provision-outreach-fleet.md) (final step)

<HARD-GATE name="smartlead-is-opt-in-never-auto">
`email_add_to_smartlead` is a **SEPARATE, deliberate step — NEVER part of any
provisioning chain.** Do NOT call it as a follow-up to
`email_provision_and_link` / `email_provision_mailbox` on your own initiative.
Add a mailbox to Smartlead **only** when the user has explicitly asked to "warm
in Smartlead" / "add as a Smartlead sender" for that specific mailbox. This is a
LOCKED product decision: provisioning a mailbox and putting it into live outreach
rotation are two different consent levels — `provision_and_link` deliberately
stops before Smartlead. (Email Admin S2.1, locked decision.)
</HARD-GATE>

## Rules (Non-Negotiable)

**PROVISIONING CONSUMES A PAID LICENSE SEAT — A FULL ORG 409s.** Zoho rejects a
new mailbox when the org has no free license seat. The provider's 5xx is mapped
to a clean **409** with the verbatim business reason (C1). A 409 on provision
means *buy/free a seat*, NOT retry — retrying just 409s again. Surface the
message to the operator; do not loop.

**`email_list_mailboxes` IS SLOW — DESIGN FOR IT.** The provider org-accounts
list is paginated: **cold ~20s**, then server-cached ~90s. The MCP client sets a
45s timeout. Do not treat a 15-20s response as a hang, do not fire it in a tight
loop, and prefer ONE list call feeding a batch over per-mailbox lookups.

**REGISTER BEFORE SMARTLEAD; SMARTLEAD NEEDS AN ACTIVE OUTREACH CONNECTION.**
`email_add_to_smartlead` 409s if the mailbox isn't registered in SpiderMail or
the brand has no active Smartlead outreach connection. Register (and ideally
health-check) first.

**HEALTH-CHECK IS ONLY TRUSTWORTHY WITH A PASSWORD.** `email_health_check` does a
REAL IMAP+SMTP login *when you pass the password* (or the mailbox is registered
with a stored one). Without either it degrades to a server-reachability probe —
which can say "ok" for a mailbox that can't actually log in.

**THIS IS PLATFORM-WIDE, super_admin-ONLY, AND AUDITED.** No brand scoping beyond
the `brand_id` you pass. Auth is `X-Admin-Key` (`SPIDERIQ_ADMIN_API_KEY`), never
a client PAT — never echo it. Every mutating action is written to
`email_admin_audit` (secrets are never recorded); `email_audit` reads it back.

## Decision tree — pick a reference

| The user wants to… | Read |
|---|---|
| connect a Zoho org to a brand, or just see what connections/mailboxes exist | [references/connect-and-inspect.md](references/connect-and-inspect.md) |
| spin up N outreach mailboxes on a domain (provision → IMAP → register → health) | [references/provision-outreach-fleet.md](references/provision-outreach-fleet.md) |
| (opt-in) add a provisioned+registered mailbox to Smartlead as a sender | [references/provision-outreach-fleet.md](references/provision-outreach-fleet.md) (final step) |
| audit all mailboxes and re-enable IMAP wherever it's off (fleet recovery) | [references/audit-and-reenable-imap.md](references/audit-and-reenable-imap.md) |
| figure out why a mailbox bounces (`domain_does_not_exist` / `553` / NXDOMAIN) or its inbox is stale | [references/diagnose-deliverability.md](references/diagnose-deliverability.md) |
| rotate / reset passwords for every mailbox on a domain | [references/rotate-passwords.md](references/rotate-passwords.md) |
| understand why provision 409s / why the list is slow / why Smartlead is opt-in | [learnings/](learnings/) |

## Surface (quick map)

All under `/api/v1/mail-admin` on `https://spideriq.ai`, `X-Admin-Key` auth,
super_admin-only. The MCP tools ship in the **mcp-admin** slice
(`@spideriq/mcp-admin`); the CLI is `spideriq email …`.

| Do | HTTP | MCP tool | CLI |
|---|---|---|---|
| List provider org connections | `GET /connections` | `email_list_connections` | `spideriq email connections` |
| Connect a provider org (Zoho EU) | `POST /connections` | `email_connect_provider` | `spideriq email connect` |
| Revoke a connection | `POST /connections/{id}/revoke` | `email_revoke_connection` | `spideriq email revoke` |
| List org mailboxes (**SLOW ~20s**) | `GET /connections/{id}/mailboxes` | `email_list_mailboxes` | `spideriq email mailboxes` |
| Provision a mailbox (**seat → 409**) | `POST /connections/{id}/mailboxes` | `email_provision_mailbox` | `spideriq email provision` |
| Enable IMAP (bulk) | `POST /connections/{id}/enable-imap` | `email_enable_imap` | `spideriq email enable-imap` |
| Set / reset a password | `POST /connections/{id}/set-password` | `email_set_password` | `spideriq email set-password` |
| Register in SpiderMail | `POST /connections/{id}/register` | `email_register_in_spidermail` | `spideriq email register` |
| Provision → IMAP → register → health | `POST /connections/{id}/provision-and-link` | `email_provision_and_link` | `spideriq email provision-and-link` |
| Health-check (IMAP+SMTP login) | `POST /connections/{id}/health-check` | `email_health_check` | `spideriq email health-check` |
| **(opt-in)** Add to Smartlead as sender | `POST /connections/{id}/add-to-smartlead` | `email_add_to_smartlead` | `spideriq email add-to-smartlead` |
| Read the god-mode audit log | `GET /audit` | `email_audit` | `spideriq email audit` |

> **12 MCP tools, 12 CLI verbs.** All take `SPIDERIQ_ADMIN_API_KEY`, never a
> client PAT. `connection_id`, `account_id` + `zuid` come from
> `email_list_mailboxes`; `connection_id` also from `email_list_connections`.

## Methods (native tool calls — from client/schema.yaml)

| Method | Does | Reference |
|---|---|---|
| `listConnections` | provider org connections (optionally one brand) | [references/connect-and-inspect.md](references/connect-and-inspect.md) |
| `connectProvider` | attach a Zoho-EU org to a brand (vault ref or inline bundle) | [references/connect-and-inspect.md](references/connect-and-inspect.md) |
| `revokeConnection` | deactivate a connection (vault token left in place) | [references/connect-and-inspect.md](references/connect-and-inspect.md) |
| `listMailboxes` | live org inventory + SpiderIQ state (SLOW ~20s cold) | [references/audit-and-reenable-imap.md](references/audit-and-reenable-imap.md) |
| `provisionMailbox` | create local_part@domain (consumes a license seat) | [references/provision-outreach-fleet.md](references/provision-outreach-fleet.md) |
| `enableImap` | bulk-enable IMAP; each target independent | [references/audit-and-reenable-imap.md](references/audit-and-reenable-imap.md) |
| `setPassword` | reset a provider mailbox password | [references/rotate-passwords.md](references/rotate-passwords.md) |
| `registerInSpiderMail` | add to mail_mailboxes (idempotent per client+email) | [references/provision-outreach-fleet.md](references/provision-outreach-fleet.md) |
| `provisionAndLink` | provision → enable-imap → register → health (no Smartlead) | [references/provision-outreach-fleet.md](references/provision-outreach-fleet.md) |
| `healthCheck` | real IMAP+SMTP login probe (trustworthy with a password) | [references/provision-outreach-fleet.md](references/provision-outreach-fleet.md) |
| `addToSmartlead` | **opt-in** — add a registered mailbox as a Smartlead sender | [references/provision-outreach-fleet.md](references/provision-outreach-fleet.md) |
| `audit` | read the god-mode audit log (filter by brand/connection) | [references/connect-and-inspect.md](references/connect-and-inspect.md) |

The envelope contract (`guidance:` per method — `use`/`next`/`warn`/
`telemetry_signal_default`, plus skill-level `intent_aliases`) lives in
[client/schema.yaml](client/schema.yaml).

## References (loaded on demand)

- **[references/connect-and-inspect.md](references/connect-and-inspect.md)** — bootstrap
  a brand's Zoho-EU connection (vault ref vs inline bundle) and read the
  connection / mailbox / audit surfaces. Start here if no connection exists yet.
- **[references/provision-outreach-fleet.md](references/provision-outreach-fleet.md)** —
  **the main recipe.** Spin up N mailboxes on a domain: provision → enable-imap →
  register → health, then (opt-in) Smartlead. Steps / Gotchas / Verify.
- **[references/audit-and-reenable-imap.md](references/audit-and-reenable-imap.md)** —
  the proven fleet-recovery path: list → find IMAP-off → bulk re-enable → verify.
- **[references/rotate-passwords.md](references/rotate-passwords.md)** — rotate every
  mailbox password on a domain and re-register so SpiderMail keeps the new one.

## See also

- `learnings/` — the three traps that bite first-timers: provisioning needs a
  free license seat (409, not retry), the mailbox list is slow on a cold call,
  and Smartlead is opt-in (never auto-chained). Starting points, **not** ground
  truth — verify against current code.
- **Sibling skills in this package** (`@spideriq/admin-skills`): `integrations`
  (provider API keys / vault — where the Zoho OAuth token actually lives),
  `manage-routing`, `opvs-admin`, `auth`, `manage-browser-profiles`,
  `manage-locations`.
- **Not this skill:** reading/sending mail from a mailbox is SpiderMail
  (`@spideriq/mail-skills`); managing the Zoho OAuth token / key vault is the
  `integrations` surface. This skill is the *control plane* that creates and
  configures the mailbox — the data plane and the credential store are elsewhere.
