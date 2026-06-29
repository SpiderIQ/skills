# Smartlead is opt-in — never auto-chain it after provisioning

## What happened

The Email Admin control plane has a full provision chain
(`email_provision_and_link`: provision → enable-imap → register → health-check)
and a *separate* tool, `email_add_to_smartlead`. The Smartlead step is
**deliberately excluded** from the chain — a LOCKED product decision from S2.1.

## Why it matters

Provisioning a mailbox and putting it into **live cold-outreach rotation** are two
different consent levels:

- A customer may want mailboxes stood up and registered in SpiderMail (so the
  data plane can poll/send) **without** them being added to Smartlead sending.
- Auto-adding every provisioned mailbox to Smartlead would silently push it into
  active outreach — exactly the kind of irreversible side effect that needs
  explicit human intent.

So `email_add_to_smartlead` runs **only** when the user has explicitly asked to
"warm in Smartlead" / "add as a Smartlead sender" for that specific mailbox.

## How to apply

- **Never** call `email_add_to_smartlead` as a follow-up to provisioning on your
  own initiative. The SKILL.md HARD-GATE codifies this.
- Add to Smartlead only on explicit instruction, and only after:
  - the mailbox is **registered** in SpiderMail (`email_register_in_spidermail`), and
  - the brand has an **active Smartlead outreach connection**.
  Missing either → the call 409s (`SmartleadLinkError`).
- Defaults are conservative: `max_email_per_day` 50, `warmup_enabled` false.

## Caveat

The Smartlead WRITE path (`SmartleadProvider.add_sender` →
`POST /email-accounts/save`) was built best-effort against Smartlead's documented
sender-create endpoint and should be verified live with a **throwaway sender**
before trusting it at scale — confirm the sender re-syncs via the provider's
account list, then remove the throwaway. Verify against current code in
`app/services/mail/outreach/smartlead.py`.
