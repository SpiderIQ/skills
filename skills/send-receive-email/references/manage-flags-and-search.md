# Search + flags — find mail, then keep the inbox tidy

Two everyday tasks: locate a past email, and manage its state (read / star /
labels). The trap in search is that it's **per-mailbox** (an `email` is required);
the trap in flags is that **labels REPLACE** the set, they don't append.

## Search

`searchMail` does full-text search over **subject + body** plus structured
filters. It searches ONE mailbox — `email` is required.

```bash
# Full-text — find emails mentioning "invoice" in Alice's mailbox
curl -s -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/mail/search?email=alice@acme.com&q=invoice&format=yaml"

# Structured filters — from a sender, subject substring, date-bounded
curl -s -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/mail/search?email=alice@acme.com&from_addr=bob@lead.com&since=2026-06-01&format=yaml"
```

- `q` is the FTS query (intent aliases: `q` / `query` / `search_query`).
- `from_addr`, `subject` are ILIKE substring filters; `since`/`before` are ISO dates.
- **`email` is required** — search has no master-inbox (all-mailboxes) mode; to
  search across mailboxes, search each one. (This differs from `getInbox`, which
  defaults to master.)
- Take a hit's numeric `id` into `getMessage` or its `thread_id` into `getThread`.

## Flags — read / star / labels

`updateMessage` patches a message's state. Only the fields you pass change.

```bash
# Mark read
curl -s -X PATCH -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/mail/messages/84213" -H "Content-Type: application/json" \
  -d '{"is_read":true}'

# Star a hot lead
curl -s -X PATCH ... -d '{"is_starred":true}'

# Re-mark unread (e.g. after previewing one you opened for the user)
curl -s -X PATCH ... -d '{"is_read":false}'
```

## WRONG

```bash
# WRONG: expecting labels to ADD to the existing set
curl -s -X PATCH -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/mail/messages/84213" -H "Content-Type: application/json" \
  -d '{"labels":["hot-lead"]}'
# → REPLACES all labels with just ["hot-lead"]. Any existing "prospect" label is GONE.
```

## RIGHT

```bash
# RIGHT: read the current labels, then send the FULL intended set
CUR=$(curl -s -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/mail/messages/84213" | jq -c '.labels // []')
# add "hot-lead" to whatever was there:
curl -s -X PATCH -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/mail/messages/84213" -H "Content-Type: application/json" \
  -d "{\"labels\": $(echo "$CUR" | jq -c '. + ["hot-lead"] | unique')}"
```

## Private notes

`updateMessage notes="…"` attaches an internal note to a message — visible in the
mailbox, never sent to anyone. Useful for leaving context for the next agent/human.

## Verify

```bash
# Star then confirm it stuck
curl -s -X PATCH -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/mail/messages/84213" -H "Content-Type: application/json" -d '{"is_starred":true}'
curl -s -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/mail/messages/84213?format=yaml" | grep is_starred
```

## Gotchas

- **`labels` REPLACES** the whole set — read-modify-write to add one.
- **search requires `email`** — no all-mailbox search; `getInbox` (no email) is
  the all-mailbox read, search is not.
- `from_addr`/`subject` are substring (ILIKE), case-insensitive.
- `message_id` everywhere here is the numeric id, not the RFC Message-ID header.
