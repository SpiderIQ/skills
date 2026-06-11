# Outreach + warmup — Smartlead / lemlist / Instantly

SpiderMail connects to cold-email providers (Smartlead, lemlist, Instantly) as
**outreach sidecars**. Each sidecar tracks the provider's sending accounts, their
**warmup** state, and deliverability **health snapshots**. This is how an agent
answers "is my warmup healthy?" / "what's my deliverability?" / "sync my senders."

This surface is **different from the rest of the skill**:

- **Brand-scoped, not mailbox-scoped:** routes are
  `/brands/{brand_id}/mail/outreach/*` — `brand_id` is the numeric brand id.
- **Two auth tiers:** reads (list/get connections, senders, health) work with a
  PAT; **writes** (`updateOutreachConnection`, `deleteOutreachConnection`,
  `syncOutreachConnection`) need **brand-admin** — a read-only token gets `403`.
- **Connections are created in the dashboard IntegrationsTab**, not here. Adding a
  Smartlead/lemlist/Instantly integration there auto-creates the sidecar
  (workspace_id, warmup_tag, lemwarm_domains). This skill **reads, edits, syncs,
  and revokes** existing sidecars; it does not create them.

## The shape

```
brand
 └─ outreach connection (sidecar)   provider=smartlead|lemlist|instantly, warmup_tag, lemwarm_domains, is_active
     └─ sender (sending account)    email_address, warmup_enabled, status, mailbox_id
         └─ health snapshot         health_score, sent/inbox/spam/bounce/reply (24h+7d), polled_at
```

## Steps

1. **See what's connected** — `listOutreachConnections(brand_id)`.
2. **See the sending accounts** — `listOutreachSenders(brand_id)` → each
   account's `warmup_enabled` + `status` + matched `mailbox_id`.
3. **Check deliverability** — `getOutreachHealthOverview(brand_id)` for the whole
   grid, or `getSenderHealth(brand_id, sender_id)` for one account.
4. **Refresh from the provider** (brand-admin) — `syncOutreachConnection(brand_id,
   connection_id)` pulls the latest senders + warmup state.

## Read the warmup/deliverability health

```bash
# Whole-brand overview — one row per sending account
curl -s -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/brands/42/mail/outreach/health/overview" | python3 -m json.tool

# One sender's latest snapshot
curl -s -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/brands/42/mail/outreach/senders/917/health" | python3 -m json.tool
# → { sender_id, email_address, provider, latest: {
#       health_score, health_label, warmup_enabled,
#       sent_24h, inbox_24h, spam_24h, bounce_24h, reply_24h,
#       sent_7d, inbox_7d, spam_7d, polled_at } }
```

The snapshot is the **latest poll, not live** — read `polled_at`. It can be
`null` for a sender never polled yet.

## Sync (brand-admin)

```bash
# Pull senders + warmup state from the provider into SpiderMail
curl -s -X POST -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/brands/42/mail/outreach/connections/5/sync"
# → { connection_id, senders_found, senders_inserted, senders_updated, mailbox_matches }
```

## WRONG / RIGHT

```bash
# WRONG: editing a connection with a read-only PAT
curl -s -X PATCH -H "Authorization: Bearer $READONLY_PAT" \
  "https://spideriq.ai/api/v1/brands/42/mail/outreach/connections/5" \
  -d '{"is_active":false}'
# → 403. Writes (update/delete/sync) need brand-admin.

# WRONG: expecting to CREATE a provider connection here
curl -s -X POST ".../brands/42/mail/outreach/connections" ...
# → there is no create route. Connections are added via the dashboard IntegrationsTab.

# RIGHT: read warmup health with a PAT; pause a sidecar as brand-admin
curl -s -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/brands/42/mail/outreach/senders" | python3 -m json.tool
curl -s -X PATCH -H "Authorization: Bearer $BRAND_ADMIN_TOKEN" \
  "https://spideriq.ai/api/v1/brands/42/mail/outreach/connections/5" \
  -H "Content-Type: application/json" -d '{"is_active":false}'
```

## Verify

```bash
# Deliverability overview should return rows (or [] if no senders), never 401/500
curl -s -o /dev/null -w "%{http_code}\n" -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/brands/42/mail/outreach/health/overview"   # → 200
```

## Gotchas

- **Brand-scoped** (`brand_id`), not a mailbox address — these don't take an `email`.
- **Writes need brand-admin** (update/delete/sync); reads are PAT-ok.
- **No create route** — connections come from the dashboard IntegrationsTab.
- Health snapshots are the latest **poll**, not live — check `polled_at`.
- `deleteOutreachConnection` cascades senders/campaigns/health but leaves the
  underlying `api_integrations` credential — the user removes that separately.
