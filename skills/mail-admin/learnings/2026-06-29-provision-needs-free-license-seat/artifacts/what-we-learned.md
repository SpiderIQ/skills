# A full org 409s on provision — free a seat, don't retry

## What happened

Provider mailboxes (Zoho EU) are billed per **license seat**. Creating a mailbox
consumes one. When the org is at its seat limit, the provider refuses the create.

The provider returns that refusal as a 5xx. Left alone, that would surface to the
agent as an opaque `502` — indistinguishable from a transient upstream blip, the
kind of thing you'd retry. The **C1 fix** (PR #2043) added a
`ProviderCapacityError` → **409** branch in `mail_admin.py`'s error mapper, placed
*before* the generic `EmailAdminError` → 502 branch, that surfaces the **verbatim
provider business message** (e.g. "no license available").

## Why it matters

A 409 from `email_provision_mailbox` / `email_provision_and_link` is a
**business-state** error, not a transient one:

- **Do NOT retry.** The seat count won't change on its own — retrying just 409s
  again and wastes calls.
- **Surface the message.** The 409 detail is the provider's actual reason; show
  it to the operator so they can free or buy a seat.
- **In a fleet loop, halt on 409.** Each provision is independent, so a 409 on
  mailbox #7 doesn't poison #1-6. Catch it per-mailbox and stop the loop — don't
  keep firing the remaining N against a known-full org.

## How to apply

```
try: provision_and_link(...)
except 409 as e:
    show e.detail to the operator ("free/buy a license seat")
    STOP the provisioning loop   # do not retry, do not continue the batch
```

## Caveat

Verify against current code — the error mapping lives in
`app/api/v1/mail_admin.py::_raise_http`. Other 409s on this surface mean
different things (`PolicyBlockedError`; `SmartleadLinkError` = unmet Smartlead
precondition), so read the message, don't assume every 409 is a seat issue.
