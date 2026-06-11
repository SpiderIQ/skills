# Attachments arrive as an inline preview — and the "retrieve_via" URL is a dead link

*Starting point, not ground truth — verify against current behaviour.*

## How attachments reach the agent

The SpiderMail poller walks each inbound message's MIME parts, extracts text from
attachments (PDF / DOCX / image-OCR / CSV / TXT / code via LiteParse), and stores
`preview` (first ~500–1500 chars) + `full_text` in the `email_attachments` table.

What an **agent over a PAT** actually gets is the **metadata + preview, inline**
on the message read:

```bash
curl -s -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/mail/messages/84213?include_attachments=true&format=yaml"
```

```yaml
attachments: # 1 attachment(s)
  - id: "…"
    filename: contract.pdf
    mime_type: application/pdf
    size_bytes: 84213
    preview: "MASTER SERVICES AGREEMENT. This agreement is entered into…"
    retrieve_via: "/api/v1/mail/attachments/{id}"   # ← NOT a served route (404)
```

`include_attachments` defaults to **true**, so you normally don't pass it.

## The trap: `retrieve_via` 404s

The YAML emits `retrieve_via: /api/v1/mail/attachments/{id}` as if you could fetch
the full extracted text there. **You cannot** — a grep of `app/` (2026-06-10)
finds no `@router.get(".../attachments/{id}")`. The only PAT-reachable attachment
text is the **inline preview**. (`/internal/mail/messages/{id}/attachments` exists
but is `X-Internal-Key`-only — for the poller, not a client.)

So:
- plan around the preview;
- if the preview is truncated and the user needs more, say so — there's no
  client call that returns the rest;
- this is a known SpiderMail bug to fix (implement `GET /mail/attachments/{id}`
  returning `full_text`/`storage_key`, or stop emitting the dead `retrieve_via`).
  Tracked in `references/gaps.md` Gap 4.

## Why it's preview-only by design

Per SpiderMail's own learnings (#8), full attachment text is deliberately NOT
pushed to the agent — large PDFs/DOCX would blow the token budget for content
that's usually mostly irrelevant. Summary + preview by default is the intended
contract; the missing full-text route is the part that's a genuine gap, not the
preview-first design.
