# A `{markdown:"..."}` post body renders blank in the editor

## Symptom
A published blog post shows its excerpt in the dashboard but the main editor body
is an empty box. The public site may still show the article (see below).

## Root cause
`content_posts.body` is contractually a **Tiptap document** (`{type:"doc",content:[...]}`).
Agents frequently send `{"markdown":"..."}` instead (markdown is an LLM's native
output). The MCP tool and skill both *documented* "Tiptap JSON" but neither
**validated** the shape — the field was a bare `object` — so the markdown blob
saved silently. The TipTap editor and the default renderer's `tiptap_html` filter
read only `type`/`content`, so a `{markdown}` body renders **blank** and its
`body_text` (search) is empty.

## Why some public sites still worked (the trap)
6 Antigravity-built tenants ship a **custom** `blog-post.liquid` that renders
`body.markdown` client-side via marked.js:
```
raw = data.markdown || data.content || data;  marked.parse(raw);
```
So those sites render markdown bodies fine — which is exactly why a naive
"convert everything to Tiptap" backfill would **break** them (they'd `marked.parse`
a Tiptap content array). Only spideriq.ai (default template) rendered blank publicly.

## Fix (2026-07-09)
Normalize at the write boundary instead of trusting the shape:
- `create_post` / `update_post` → `_normalize_post_body_for_storage` converts
  `{markdown}` / `{html}` to Tiptap (`markdown_to_tiptap`, `html2text` for HTML).
- A **transitional** `markdown` mirror + `_authored` marker are kept on the stored
  body so the custom marked.js sites keep rendering. Drop the mirror once those
  templates switch to `{{ post.body | tiptap_html }}`.
- Editor shows a mode badge (Markdown / HTML / Rich text) from `_authored`.
- Additive backfill (`backfill_post_body_tiptap.py`) fixes the 56 existing posts.

## Rule for agents
Send a Tiptap `body` when you have one. If you only have markdown or HTML, you may
send `{markdown:"..."}` / `{html:"..."}` — the server converts it. Never assume a
raw markdown string in `body` will render; it must become a Tiptap doc (the server
now guarantees that).
