# Organise the inbox — folders, bulk triage, snooze, labels, views

Beyond reading and replying, an agent keeps the inbox in order. Five tools:
folders, bulk actions, snooze, label definitions, and saved views. The traps:
bulk `delete` is irreversible, label DEFINITIONS are separate from putting a label
ON a message, and a saved view is a filter you apply via `getInbox(view_id=…)`.

## Folders

```bash
curl -s -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/mail/folders?email=alice@acme.com&format=yaml"
# → [{ name: INBOX, total, unread }, { name: Sent, … }, { name: Drafts, … }, { name: Trash, … }]
```
`email` is **required** (folders are per-mailbox; there is no client-wide folder
list — omitting `email` is a 422). Use a folder name in `getInbox?folder=Sent`.
Note "Drafts" is a folder filter, not a writable drafts store — there is no
create-draft endpoint.

## Bulk triage (the fast path)

One action across up to **100** messages. `action ∈ mark_read | mark_unread |
archive | delete | add_label` (add_label needs `label`).

```bash
# Mark a page read in one call
curl -s -X POST -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/mail/messages/bulk" -H "Content-Type: application/json" \
  -d '{"message_ids":[84213,84214,84215],"action":"mark_read"}'

# Tag a batch as hot-lead
curl -s -X POST ... -d '{"message_ids":[84213,84220],"action":"add_label","label":"hot-lead"}'
```

### WRONG / RIGHT

```bash
# WRONG: bulk delete to "clean up", no confirmation
-d '{"message_ids":[84213,84214,84215],"action":"delete"}'   # irreversible — gone.

# RIGHT: archive (reversible) unless the user explicitly said delete
-d '{"message_ids":[84213,84214,84215],"action":"archive"}'
```

- `delete` is destructive and has no undo — prefer `archive`; only `delete` when
  the user explicitly asked.
- `add_label` requires the `label` field, or it's a no-op.
- Max 100 ids per call — page larger batches.

## Snooze

Hide a message until a timestamp; it auto-returns to its folder then.

```bash
curl -s -X POST -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/mail/messages/84213/snooze" -H "Content-Type: application/json" \
  -d '{"snoozed_until":"2026-06-12T09:00:00Z"}'

curl -s -H "Authorization: Bearer $SPIDERIQ_PAT" "https://spideriq.ai/api/v1/mail/snoozed?format=yaml"
curl -s -X DELETE -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/mail/messages/84213/snooze"   # bring it back now
```
`snoozed_until` must be a future ISO-8601 timestamp. A snoozed message leaves the
inbox until then.

## Label definitions vs applying a label

Two different things — the #1 confusion:

| You want to… | Call |
|---|---|
| Create / list / recolour the label PALETTE | `createLabel` / `listLabels` / `updateLabel` |
| Put a label ON a message | `updateMessage labels=[…]` or `bulkUpdateMessages add_label` |

```bash
# Define a label (name + hex colour)
curl -s -X POST -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/mail/labels" -H "Content-Type: application/json" \
  -d '{"name":"hot-lead","color":"#EF4444"}'
```
`color` is `#RRGGBB` (default `#6B7280`); `name` ≤50 chars. Deleting a definition
doesn't strip the raw string from already-tagged messages until they're re-saved.

## Saved views

A view is a named filter bundle you apply with `getInbox(view_id=…)`.

```bash
# Save "unread starred, across two mailboxes"
curl -s -X POST -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/mail/views" -H "Content-Type: application/json" \
  -d '{"name":"Hot inbox","filter_config":{"mailboxes":["alice@acme.com"],"unread_only":true,"starred_only":true},"is_shared":false}'
# → { id: 7, ... }

# Apply it
curl -s -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/mail/inbox?view_id=7&format=yaml"
```
- `is_shared=true` exposes the view to every dashboard user of the client; **only
  the creator can edit** a view (even a shared one).
- `filter_config` keys: `mailboxes[]`, `unread_only`, `starred_only`, `has_attachments`.

## Verify

```bash
# Create a view, apply it, confirm it filters
VID=$(curl -s -X POST -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/mail/views" -H "Content-Type: application/json" \
  -d '{"name":"Unread","filter_config":{"unread_only":true}}' | jq -r .id)
curl -s -H "Authorization: Bearer $SPIDERIQ_PAT" "https://spideriq.ai/api/v1/mail/inbox?view_id=$VID&format=yaml"
```

## Gotchas

- bulk `delete` = no undo; prefer `archive`.
- label DEFINITIONS (`/mail/labels`) ≠ applying a label (`updateMessage`/`bulk add_label`).
- a view is a filter applied via `getInbox(view_id=…)`; views are creator-mutable only.
- "Drafts" is a folder filter, not a writable drafts store — no create-draft route exists.
