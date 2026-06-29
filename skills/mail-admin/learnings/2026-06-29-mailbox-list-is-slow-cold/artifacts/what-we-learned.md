# The mailbox list is slow cold (~20s) — one list, then batch

## What happened

`email_list_mailboxes` reads the provider's org-accounts list **live**. That list
is paginated at the provider, so a **cold** call takes roughly **20 seconds**. The
server caches the result for ~90s, so a follow-up call within that window is fast.
The MCP tool sets a deliberate **45s** client timeout
(`LIST_MAILBOXES_TIMEOUT_MS`) so a healthy-but-slow read isn't aborted mid-flight.

## Why it matters

Two ways naive agents waste time (or break):

1. **Treating ~20s as a hang and retrying.** A retry just kicks off *another*
   cold read — slower, not faster. Wait for the first call.
2. **Re-listing per mailbox in a loop.** The audit/enable-imap and rotate flows
   each need `account_id` + `zuid` for many mailboxes. Calling the list once per
   mailbox turns a 20s operation into minutes. One list call returns the **whole**
   annotated inventory (`imap_enabled`, `registered`, `smartlead_sender`,
   `account_id`, `zuid`, `email`).

## How to apply

- **List once, act in memory.** `email_list_mailboxes` → filter
  (`imap_enabled == false`, or by domain) → build the batch → one
  `email_enable_imap` (bulk) or a per-mailbox `set_password` loop.
- **Set generous expectations.** Don't abort or retry before ~30-45s on a cold
  call; warm calls (within ~90s) come back quickly.
- **Never put the list inside the per-mailbox loop.**

## Caveat

The exact cold timing varies with org size and provider load — ~20s is typical,
not a guarantee. The 45s timeout and ~90s cache are the contract to design
against; verify the current values in `packages/mcp-tools/src/admin/email.ts` if
behavior changes.
