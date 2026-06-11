# Read mail — inbox, message, thread, session, attachments

The read side is a direct DB query (instant, no queue). Four entry points plus a
bootstrap. The traps are: which inbox you asked for, the read side-effect, and
how attachments arrive.

## Steps

1. **Bootstrap a mailbox** — `getSession?email=<addr>` returns the mailbox info,
   unread count, and recent messages in ONE call. Best first move when you'll
   work a specific mailbox.
2. **Or browse** — `getInbox` with **no `email`** is the **Master Inbox** (every
   message across every mailbox, newest first). Pass `email=` to scope to one.
3. **Open one** — `getMessage?message_id=<numeric id>`. This returns the full
   clean body + headers **and marks the message read**.
4. **See the conversation** — `getThread?thread_id=<id>` returns all messages in
   the thread in order. Use the latest message's `id` as the reply target.
5. **Token economy** — append `?format=yaml` (or `md`), or set
   `SPIDERIQ_FORMAT=yaml`. Inbound YAML is ~37x smaller than raw MIME.

## Master inbox vs one mailbox (the #1 surprise)

```bash
# Master Inbox — EVERYTHING across all the tenant's mailboxes
curl -s -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/mail/inbox?unread_only=true&format=yaml"

# One mailbox only
curl -s -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/mail/inbox?email=alice@acme.com&format=yaml"
```

Omitting `email` is NOT "the default mailbox" — it is **all of them**. If the
user said "check Alice's inbox," pass `email=alice@acme.com` or you'll surface
other mailboxes' mail.

## Reading marks read — know the side effect

```bash
# This MARKS THE MESSAGE READ as a side effect:
curl -s -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/mail/messages/84213?format=yaml"
```

If you're only previewing for the user and want to preserve unread state, read
the summary from `getInbox`/`searchMail` rows instead of opening the message — or
re-mark it unread afterwards with `updateMessage is_read=false`.

## Threads

`thread_id` is a field on every message (computed from the RFC References /
In-Reply-To chain — Priority: first Message-ID in References → In-Reply-To → own
Message-ID). To reply in-thread, fetch the thread, then reply to the **latest**
message's numeric `id`:

```bash
curl -s -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/mail/threads/abc123@acme.com?format=yaml"
# → ordered messages; take the last one's `id` as reply_to_message_id
```

## Attachments — inline preview only

Inbound attachments are extracted by the poller (PDF / DOCX / image-OCR / CSV /
TXT / code) and their summaries ride **inline** on the message:

```bash
curl -s -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/mail/messages/84213?include_attachments=true&format=yaml"
# → attachments: [{ id, filename, mime_type, size_bytes, preview: "first ~500 chars…" }]
```

- `include_attachments` defaults to **true** — you usually don't need to set it.
- You get a **preview** (first ~500 chars of extracted text), not the full text.
  There is **no PAT endpoint to fetch the full attachment text** — the YAML emits
  a `retrieve_via: /api/v1/mail/attachments/{id}` hint, but that route is **not
  served** (see `gaps.md`). Work from the preview; if it's truncated, say so.
- Per the SpiderMail design, full text is intentionally not pushed to the agent
  (token economy) — preview + summary only.

## Quarantine (security)

The inbound scanner can auto-quarantine a message it judges to be a prompt-injection
attack. Quarantined messages are **kept out of `getInbox`** on purpose:

```bash
curl -s -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/mail/quarantine?format=yaml"          # list held messages
curl -s -X POST -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/mail/messages/84213/release"           # release a false positive
```

Only release after a human judges the content safe — quarantine exists to stop
injection reaching the agent.

## Verify

```bash
# One-call bootstrap of a mailbox — confirms auth + mailbox + recent state
curl -s -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/mail/session?email=alice@acme.com&include_recent=5&format=yaml"
```

## Gotchas

- No `email` on `getInbox` = master inbox (all mailboxes), not a default.
- `getMessage` marks read; list/search rows do not.
- `message_id` is the numeric DB id; `thread_id` is the thread root id; the RFC
  `Message-ID` header is a different string — don't cross them.
- Attachments: preview inline only; no full-text fetch over PAT (`gaps.md`).
- A `{ count: 0 }` inbox is a normal empty read, not an error.
