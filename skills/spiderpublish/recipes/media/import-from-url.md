# recipes/media/import-from-url

Pull a file (or batch of files) **from any public URL** into the tenant's SpiderMedia R2 bucket — one MCP call. Auto-proxies Instagram / Facebook / Twitter CDN URLs that 403 direct fetches.

## When to use

- Importing an asset a client linked via Dropbox / Google Drive / WeTransfer / Notion attachment without the round-trip through local download + upload.
- Mirroring a public Instagram / Facebook / Twitter image into tenant storage so it survives the source post being deleted.
- Bulk-importing 20+ external URLs into a single folder (logo packs, brand kits, OG-image batches).
- Building an automation that ingests media references from another tool (Airtable, Sheets) into SpiderMedia.
- Pattern: "this URL has the file — put it in our bucket."

## Prerequisites

- A PAT scoped to the tenant.
- A public URL (or list of URLs) — the importer fetches server-side, so the URL must be reachable from the SpiderMedia gateway.

## Single URL

```
import_from_url({
  url:    "https://cdn.example.com/hero-image.jpg",
  folder: "marketing-2026"
})
# → {
#     success: true,
#     file: {
#       key: "marketing-2026/hero-image.jpg",
#       url: "https://media.cdn.spideriq.ai/<tenant>/marketing-2026/hero-image.jpg",
#       size: 384712,
#       content_type: "image/jpeg"
#     }
#   }
```

`folder` is optional but recommended — it puts the file in a logical bucket prefix. Without it, files land at the bucket root.

### Batch

```
import_from_url({
  urls: [
    { url: "https://cdn.example.com/logo-light.svg", filename: "logo-light.svg" },
    { url: "https://cdn.example.com/logo-dark.svg",  filename: "logo-dark.svg" },
    { url: "https://cdn.example.com/icon.png" }       # filename omitted → derived from URL
  ],
  folder: "brand-kit"
})
# → { success: true, files: [ {key, url, size, content_type}, ... ] }
```

Each item is `{url, filename?}`. The optional `filename` overrides what's parsed from the URL — useful when the URL has a query-string suffix (`?v=12345`) or a hash-cache buster.

## Auto-proxy for social CDNs

Instagram, Facebook, and Twitter image CDNs reject direct fetches without specific referrer / cookie state. The importer detects these URLs and routes them through a proxy:

```
import_from_url({
  url: "https://scontent-fra3-1.cdninstagram.com/v/.../image.jpg",
  folder: "client-acme/social"
})
# → auto-detects IG CDN, routes via proxy, lands the file
```

Force proxy on for any URL (if the importer doesn't auto-detect):

```
import_from_url({
  url:       "https://unusual-cdn.example.com/image.jpg",
  folder:    "imports",
  use_proxy: true
})
```

## Content-type sniffing + extension

The importer:

1. Sends `HEAD` first to read `Content-Type` and `Content-Length`.
2. If the URL has no extension, derives one from `Content-Type` (`image/png` → `.png`, `video/mp4` → `.mp4`).
3. If the URL has a wrong extension (`.jpg` for an `image/webp`), the **URL extension wins** in the saved filename — but `content_type` in the response is the sniffed truth. Audit when this matters for client-side rendering.

## Folder organisation

Recommended structure:

```
<bucket-root>/
  brand-kit/                 — logos, icons, brand-color swatches
  marketing-2026/             — campaign assets by year
  client-<slug>/              — per-client subfolders if you're an agency
    landing-2026-05/
    social/
    proofs/
  staging/                    — pre-production assets awaiting approval
```

Pass `folder: "client-acme/social"` — slashes inside `folder` create nested prefixes.

## Steps

```
1. import_from_url({ url, folder })          — pull the file
2. list_files({ type: "image", limit: 5 })   — confirm it landed
3. (use the returned .url in a page's hero block, OG-image, etc.)
```

For a campaign batch:

```
1. import_from_url({ urls: [...20 items...], folder: "campaign-q3" })
2. list_files({ limit: 50 })                  — confirm all 20 landed
3. (handle any failures by checking each item's response status)
```

## Gotchas

- **The fetch happens server-side.** The URL must be reachable from SpiderMedia's gateway (egress IPs). URLs requiring cookies / auth headers won't work — proxy via `use_proxy: true` if the CDN is on the auto-detect list, otherwise the import fails.
- **No deduplication.** Two imports of the same URL create two files (unless `filename` is identical AND folder is identical AND object-storage overwrites are enabled). Check `list_files` before bulk-importing if dedup matters.
- **Large files (>100 MB) may time out.** SpiderMedia's import has a per-request timeout; videos over 100 MB should use `upload_local_file` (chunked) instead.
- **`use_proxy: true` adds latency** (proxy fetches the URL, streams to SpiderMedia, then SpiderMedia stores). For known-clean direct-fetchable URLs, leave `use_proxy` unset.
- **Tenant storage quota is enforced.** A bulk import that would exceed the quota fails partway — check `get_media_stats` before importing large batches; see [`tighten-media-budget.md`](tighten-media-budget.md).
- **Imports DON'T trigger image optimization automatically** — the file lands as-is. For WebP conversion / resize, post-process via separate tooling.

## Verify

```
list_files({ type: "image", limit: 10 })
# → confirms the new file is in the list

get_media_stats()
# → file count + storage_used confirms it landed and budget is OK
```

For a known key:

```bash
curl -I "https://media.cdn.spideriq.ai/<tenant>/<folder>/<filename>"
# HTTP/2 200
# content-type: image/jpeg
# content-length: 384712
```

## Anti-patterns

- **Importing the same URL 20× into a loop** because dedup isn't automatic. Check `list_files` first or use the `filename` override + a known stable name.
- **Importing huge videos (>500 MB) via `import_from_url`.** Use `upload_local_file` (chunked, resumable) for large videos.
- **Bypassing folder organisation** — `folder: ""` means root. Six months later you have 400 files at root and no way to find anything.
- **Importing user-supplied URLs without validation.** A malicious URL could point at an internal-network address if SpiderMedia's gateway egresses near it. Always validate the URL scheme + host against an allowlist for user-facing flows.
- **Trusting the file extension in the URL.** Sniff `content_type` from the response — a `.jpg` URL can be serving WebP. Some image renderers care.

## Verify the recipe → tool

```bash
./scripts/find-tool-for-intent.sh "import a file from a URL into SpiderMedia"
# Top-1 should be: recipes/media/import-from-url.md
```

## See also

- [`bulk-upload.md`](bulk-upload.md) — upload from local files (uses `upload_local_file` / `upload_local_directory`)
- [`tighten-media-budget.md`](tighten-media-budget.md) — check quota + delete unused before importing a large batch
- [`../marketplace/pick-bg-video.md`](../marketplace/pick-bg-video.md) — when the asset is a curated marketplace bg-video, NOT a URL import
- [`../content/scroll-video-hero.md`](../content/scroll-video-hero.md) — chains an `import_from_url` (video) → `video_to_scroll_sequence` for cinematic heroes
- [`../reference/tool-surface.md`](../reference/tool-surface.md) — the media tool family + `@spideriq/mcp` vs `@spideriq/mcp-publish` (media tools are in both)
