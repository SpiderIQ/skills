# A big compendium comes back as a URL, not inline text

**Starting point, not ground truth — verify against current code.**

## The surprise

For most sites, `markdown_compendium` is the cleaned markdown, right there in the
results. For a large crawl it **isn't** — you get a download URL instead, and code
that always reads `markdown_compendium` as a string sees something unexpected.

## Why — 3-tier storage by size

| Compendium size | Where it lives | How you get it |
|---|---|---|
| < 1 MB | inline in the response | direct (`markdown_compendium`) |
| 1–10 MB | PostgreSQL | via a follow-up API fetch |
| > 10 MB | Cloudflare R2 | a **presigned download URL** |

The `compendium` metadata object tells you which tier was used
(`storage_location`). Check it before assuming inline text.

## The 24-hour trap

R2 presigned URLs **expire after 24 hours**. A URL you cached yesterday returns a
`403` today even though it looks valid. The fix is simple: **re-fetch**
`GET /jobs/{job_id}/results` — the API mints a fresh presigned URL on each read.

## Keeping responses small

- `compendium.include_in_response: false` — get the URL/metadata, skip the inline
  blob, for big crawls you'll fetch separately.
- `compendium.max_chars` — cap the size (truncates beyond).
- `compendium.cleanup_level: minimal` — ~30% of `raw`, biggest token savings.
- `compendium.enabled: false` — skip it entirely if you only want contacts.

## Rule of thumb

- Don't assume `markdown_compendium` is always inline — read `storage_location`.
- Treat any compendium download URL as short-lived; re-fetch `/results` for a fresh
  one rather than storing the URL.
- For LLM-context use, `cleanup_level: minimal` + a sane `max_chars` keeps both the
  response and your token bill down.
