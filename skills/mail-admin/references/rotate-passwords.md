# Rotate passwords for every mailbox on a domain

Reset the provider password for a fleet of mailboxes, then re-register so
SpiderMail's stored copy matches — otherwise the data plane's logins start
failing the moment the provider password changes.

Prereq: a `connection_id` — see [connect-and-inspect.md](connect-and-inspect.md).

## The two-step-per-mailbox rule

`set_password` changes the password **at the provider only**. SpiderMail keeps
its own copy (used for IMAP/SMTP). So every rotation is **two calls per mailbox**:

```
set-password (provider)  →  register (re-store the new password in SpiderMail)
```

Skip the re-register and SpiderMail will keep trying the old password and the
mailbox goes silent.

## Steps

1. **Inventory the domain (one SLOW call).** Get `account_id` + `zuid` + `email`
   for every mailbox; filter to the domain you're rotating.

   ```bash
   spideriq email mailboxes <connection_id>   # cold ~20s; filter to @target-domain.com
   ```

   MCP: `email_list_mailboxes({ connection_id })`.

2. **For each mailbox: set the new provider password.** Target by
   `account_id` + `zuid`. The password is never audited.

   ```bash
   spideriq email set-password --connection-id <connection_id> \
     --account-id <acct> --zuid <zuid> \
     --email jane@target-domain.com \
     --password 'N3wStr0ngPass!'
   ```

   MCP: `email_set_password({ connection_id, account_id, zuid, password, email })`.

3. **Re-register the mailbox with the new password** (idempotent per
   client+email — updates the stored password, no duplicate row):

   ```bash
   spideriq email register --connection-id <connection_id> \
     --email jane@target-domain.com --password 'N3wStr0ngPass!'
   ```

   MCP: `email_register_in_spidermail({ connection_id, email, password })`.

4. **Health-check with the new password** (the trustworthy login probe):

   ```bash
   spideriq email health-check --connection-id <connection_id> \
     --email jane@target-domain.com --password 'N3wStr0ngPass!'
   ```

   MCP: `email_health_check({ connection_id, email, password })` → expect
   `imap_ok: true`, `smtp_ok: true`.

## WRONG → RIGHT

```
# WRONG — rotate at the provider, forget SpiderMail
spideriq email set-password … --password 'new'     # provider updated
# SpiderMail still has the OLD password → IMAP/SMTP logins start failing
```

```
# RIGHT — rotate, then re-register so both sides match
spideriq email set-password … --password 'new'
spideriq email register … --password 'new'         # SpiderMail now matches
spideriq email health-check … --password 'new'     # imap_ok + smtp_ok
```

## Gotchas

- **`account_id` + `zuid` come from `email_list_mailboxes`**, not the email.
- **Re-register is mandatory after every rotation.** It's idempotent per
  (client, email), so re-running just refreshes the stored password.
- **`password` must be ≥8 chars.**
- **No bulk set-password.** Unlike `enable-imap`, password reset is one mailbox
  per call — loop over the filtered inventory.
- **Health-check needs the password to be meaningful.** Without it (and without a
  registered stored password) the probe is reachability-only.

## Verify

- `email_health_check({ connection_id, email, password: <new> })` →
  `imap_ok: true`, `smtp_ok: true` for each rotated mailbox.
- `email_audit({ connection_id })` shows the `set_password` + `register` actions
  with `result: ok` (passwords are redacted in the summary).
- SpiderMail continues polling/sending with no login errors after the rotation.
