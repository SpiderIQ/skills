# Audit all mailboxes + re-enable IMAP where it's off

The proven fleet-recovery path. When SpiderMail stops polling a brand's
mailboxes, the usual cause is IMAP got toggled off at the provider (a Zoho org
setting change, a re-provision, a support action). Inventory the org, find the
IMAP-off mailboxes, bulk re-enable.

Prereq: a `connection_id` — see [connect-and-inspect.md](connect-and-inspect.md).

## Steps

1. **Inventory the org (one SLOW call).** The list is annotated with SpiderIQ
   state per mailbox: `imap_enabled`, `registered` (in SpiderMail),
   `smartlead_sender`, plus the `account_id` + `zuid` you need to act.

   ```bash
   spideriq email mailboxes <connection_id>   # cold ~20s, then cached ~90s
   ```

   MCP: `email_list_mailboxes({ connection_id })` →
   `{ mailboxes: [{ email, account_id, zuid, imap_enabled, registered, smartlead_sender }, …], count }`.

2. **Select the IMAP-off mailboxes.** Filter the list to `imap_enabled == false`.
   Build a `targets` array of `{account_id, zuid, email}` from those rows. (Do
   this from the single list result — do NOT call the list per-mailbox.)

3. **Bulk re-enable in one call.** Each target is enabled independently — one
   failure does not abort the rest.

   ```bash
   spideriq email enable-imap --connection-id <connection_id> \
     --targets '[
       {"account_id":"<a1>","zuid":"<z1>","email":"jane@d.com"},
       {"account_id":"<a2>","zuid":"<z2>","email":"bob@d.com"}
     ]'
   ```

   MCP: `email_enable_imap({ connection_id, targets: [...] })` →
   `{ results: [...], enabled: N, failed: M }`.

4. **Inspect the per-target results.** `enabled` / `failed` are counts; `results`
   has the per-mailbox outcome. Re-target any that failed (often a transient
   provider error — safe to re-send just the failed ones).

## WRONG → RIGHT

```
# WRONG — call the slow list once per mailbox, enable one at a time
for m in $mailboxes; do
  spideriq email mailboxes <id>            # ~20s EACH — minutes wasted
  spideriq email enable-imap … --targets '[{…one…}]'
done
```

```
# RIGHT — one list, one bulk enable
spideriq email mailboxes <id>              # ONE ~20s call → the whole inventory
# filter imap_enabled==false → build targets[]
spideriq email enable-imap <id> --targets '[ …all the off ones… ]'   # one bulk call
```

## Gotchas

- **`account_id` + `zuid` ≠ the email address.** Both come from
  `email_list_mailboxes`; enable-imap targets them, not the email.
- **IMAP-off blocks polling even when registered.** A mailbox can be
  `registered: true` in SpiderMail and still go silent if `imap_enabled` is
  false — that's the exact failure this recipe fixes.
- **The list is the bottleneck, not the enable.** One cold list (~20s) feeds the
  whole batch; the bulk enable is fast. Never loop the list.
- **A mailbox that's off AND unregistered** needs both `enable-imap` and
  `register` — see [provision-outreach-fleet.md](provision-outreach-fleet.md).

## Verify

- Re-run `email_list_mailboxes({ connection_id })` (now warm-cached) — the
  previously-off mailboxes show `imap_enabled: true`.
- `email_health_check({ connection_id, email, password })` on a sample →
  `imap_ok: true`.
- SpiderMail resumes polling those mailboxes on its next sweep.
