# Connect a provider org + inspect connections / mailboxes / audit

The bootstrap surface. Before you can provision anything you need a **connection**
(a brand ↔ provider-org link backed by a vault OAuth token). One connection per
brand-org; reuse its `connection_id` for every other call.

## Connect a Zoho-EU org to a brand

Two ways to supply the OAuth token:

### Attach an existing vault ref (preferred)

If the brand's Zoho org token is already in the vault (the `integrations` surface
stores it — e.g. `apiint:106`), attach it by reference. No secrets pass through
this call.

```bash
spideriq email connect \
  --brand-id 9 \
  --provider zoho --data-center eu \
  --vault-key-ref apiint:106 \
  --label "VayaPin Zoho EU org"
```

MCP: `email_connect_provider({ brand_id: 9, provider: "zoho", data_center: "eu", vault_key_ref: "apiint:106", label: "VayaPin Zoho EU org" })`

### Inline OAuth bundle (stored in vault first)

If the token isn't in the vault yet, pass the bundle inline — it is stored in the
vault, then attached. `refresh_token` + `client_id` + `client_secret` are
**required together**; `scope` defaults to `ZohoMail.organization.accounts.ALL`.

```bash
spideriq email connect \
  --brand-id 9 --provider zoho --data-center eu \
  --refresh-token "$ZOHO_REFRESH" \
  --client-id "$ZOHO_CLIENT_ID" \
  --client-secret "$ZOHO_CLIENT_SECRET"
```

MCP: `email_connect_provider({ brand_id, refresh_token, client_id, client_secret })`

## Inspect what exists

```bash
spideriq email connections                 # all brands
spideriq email connections --brand-id 9    # one brand
```

MCP: `email_list_connections({ brand_id: 9 })` → `{ connections: [...], count }`.
Each row has the `connection_id` (uuid) you pass everywhere else, plus
`provider`, `data_center`, `status`, `label`, and whether a vault token is
attached (never the token).

Inventory a connection's mailboxes (live from the provider, annotated with
SpiderIQ state):

```bash
spideriq email mailboxes <connection_id>   # SLOW — cold ~20s, then cached ~90s
```

MCP: `email_list_mailboxes({ connection_id })`. See
[audit-and-reenable-imap.md](audit-and-reenable-imap.md) for what the annotations
mean and how to act on them.

## Read the audit log

Every mutating action is recorded (secrets stripped):

```bash
spideriq email audit --brand-id 9 --limit 50
spideriq email audit --connection-id <connection_id>
```

MCP: `email_audit({ brand_id: 9, limit: 50 })`.

## Revoke a connection

Deactivates the connection; the vault token and any provisioned mailboxes are
left untouched.

```bash
spideriq email revoke <connection_id>
```

MCP: `email_revoke_connection({ connection_id })`.

## WRONG → RIGHT

```
# WRONG — try to provision without a connection
spideriq email provision --connection-id ??? …   # there is no connection_id yet
```

```
# RIGHT — connect once, then reuse the connection_id
spideriq email connect --brand-id 9 --vault-key-ref apiint:106   # → connection_id
spideriq email mailboxes <connection_id>                          # inventory it
spideriq email provision-and-link --connection-id <connection_id> …
```

## Gotchas

- **`vault_key_ref` and the inline bundle are mutually exclusive** — pass one.
  Inline `refresh_token` requires `client_id` + `client_secret` too.
- **Prefer the vault ref.** Pasting raw OAuth secrets works (they're stored in
  the vault, never audited) but attaching an existing `apiint:` ref keeps secrets
  out of the call entirely.
- **The Zoho OAuth token itself lives in the `integrations`/vault surface**, not
  here. If the token is bad/expired you'll see a `502 provider auth failed` —
  fix it on the integrations surface, not by re-connecting.
- **Auth is `X-Admin-Key`** (`SPIDERIQ_ADMIN_API_KEY`), never a client PAT.

## Verify

- `email_list_connections({ brand_id })` shows the new connection with
  `status: active` and a vault token attached.
- `email_list_mailboxes({ connection_id })` returns the org's mailboxes (proves
  the token actually authenticates against the provider).
