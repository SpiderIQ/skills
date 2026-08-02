# Media — bulk upload, import from URL, tighten the media budget

SpiderMedia stores assets on R2 and serves derivatives from `media.spideriq.ai`. URL-based
media ops (import, list, delete, video status) and local uploads use the media tools; the
dashboard surface is `/api/v1/dashboard/content/media/...` and the catalog
`/api/v1/dashboard/media/catalog/...`. Deleting an uploaded asset may need a dual-row cleanup
(catalog asset + legacy `content_media`) — the tighten-budget recipe covers it.

**Read when:** bulk-uploading a folder of images, importing media (incl. video) from a URL, or
auditing/trimming a tenant's media footprint.


---

## Bulk Upload

Upload a local file or directory to SpiderMedia — **one tool call**. Scroll-sequence folders auto-optimize on the way up.

**Kills the pinggy / serveo / localhost.run / catbox.moe tunnel hack.** Those tunnels inject HTML interstitials on first request that SpiderMedia happily saves as `.webp` with 200 OK, producing black frames in your scroll-sequence. Never again.

### The one-shot path (v0.9.4+)

#### MCP — recommended

```
upload_local_directory(
  local_dir = "./frames/",
  folder = "scroll-sequences/hero"
)
```

Returns:
```json
{
  "success": true,
  "policy": "scroll-sequence",
  "auto_optimize": true,
  "preserve_filename": true,
  "bytes_before_optimize": 201326592,
  "bytes_after_optimize": 8388608,
  "reduction_pct": 96,
  "uploaded": [
    {"filename": "frame_0001.webp", "public_url": "https://media.cdn.spideriq.ai/clients/.../scroll-sequences/hero/frame_0001.webp", "key": "scroll-sequences/hero/frame_0001.webp", "size": 72341},
    ...
  ],
  "warnings": [],
  "totals": {"count": 120, "uploaded": 120, "failed": 0, "bytes": 201326592}
}
```

Because the folder starts with `scroll-sequences/`, the tool:
1. Auto-enables `auto_optimize=true` → runs Sharp locally: every image → WebP quality 75, max 1920px wide.
2. Auto-enables `preserve_filename=true` → the CDN key is `{folder}/{filename}` exactly, so `sys-scroll-sequence` with `{base_url, pattern, count}` resolves to the right URLs.

#### CLI

```bash
spideriq media upload ./frames/ --folder scroll-sequences/hero
```

Same auto-enabled defaults for scroll-sequences. Add `--no-auto-optimize` if your frames are already tuned.

#### Single file

```
upload_local_file(local_path = "./logo.webp", folder = "brand")
```

Or `spideriq media upload ./logo.webp --folder brand`.

### Weight budget

Server enforces hard ceilings — the MCP tool also shows warnings above the soft line:

| Target folder | Per-file hard | Batch total hard | Soft warning |
|---|---|---|---|
| `scroll-sequences/*` | 500 KB | 20 MB | 200 KB / 10 MB |
| general (everything else) | 20 MB | 500 MB | — |
| `video/*` MIME | 500 MB | 500 MB | — |

If you hit the hard ceiling, the response comes back with `suggested_action` pointing at `auto_optimize=true`. If you're already using that, the files genuinely are too heavy — drop quality or dimensions.

### When to use

- You have 5+ local files to host on the CDN (scroll-sequence frames, logos, pre-produced banners, PDFs).
- You're migrating from Tilda / Wix / Figma and have a local asset dump you want on SpiderMedia.
- You need predictable CDN keys (`preserve_filename=true`) — scroll-sequence `{base_url, pattern, count}` absolutely requires this.
- You want client-side WebP optimization without writing a Sharp pipeline yourself.

### When NOT to use

- Single file → just use `upload_local_file` directly. Still fast, one tool call.
- You're starting from a **video** — use [recipes/scroll-sequence](../SKILL.md) instead. `video_to_scroll_sequence` runs `extract_frames` server-side and never round-trips through your local disk.
- You can already reach the files via a public URL → use `media_import_from_url` with the batch form (pass `preserve_filename: true` per item if you need deterministic keys).

### Sharp is an optional peer dep

`auto_optimize=true` needs `sharp`. `@spideriq/mcp-publish` lists it as `optionalDependencies`, so:
- On macOS / Linux x64/arm64 / Windows x64: installed automatically.
- On unsupported platforms or if the install failed: the tool logs a warning and uploads originals.
- If originals blow through the scroll-sequence ceiling, the server returns 400. Install Sharp manually (`npm install sharp`) or switch to manually-pre-optimized frames.

### Common variants

#### Filter the directory

```
upload_local_directory(
  local_dir = "./exports/",
  folder = "migrations/homepage",
  pattern = "hero_*.png"
)
```

Only files matching `hero_*.png` get uploaded. Pattern is a simple glob (regex-ish — `*` matches any run of chars, `.` is literal).

#### Non-scroll-sequence + preserve filenames

```
upload_local_directory(
  local_dir = "./brand-assets/",
  folder = "brand",
  preserve_filename = true
)
```

For migrations where hard-coded HTML references `brand/logo.png` — `preserve_filename=true` keeps the key exactly.

#### Manual quality tuning

```
upload_local_directory(
  local_dir = "./frames/",
  folder = "scroll-sequences/hero",
  quality = 65,        # smaller files, slightly lower quality
  max_width = 1280      # half-resolution for mobile-first
)
```

#### Videos for `video_to_scroll_sequence`

```
upload_local_file(
  local_path = "./product-demo.mp4",
  folder = "sources/product-demo"
)
```

Then pass `video_url` to `video_to_scroll_sequence`. 500 MB per-file cap lets you upload a 1080p source without splitting.

### Files in this skill

- `SKILL.md` — this file (human-readable recipe)
- `shell.md` — shell/curl fallback for agents without a TS/MCP runtime
- `impl.ts` — self-contained Node 18+ TypeScript reference (uses native `fetch` + `fs`)

### Key rules

1. **Filenames are preserved on scroll-sequences** — the tool auto-enables `preserve_filename=true` there. For other folders it defaults to `false` (LLM11 prepends a timestamp).
2. **Folder is flat** — don't use subdirectories in the `folder` param; pass the full path like `scroll-sequences/hero` as one string.
3. **Rate limit** — 100 req/min default. Batch endpoint sends ONE request for N files, so you don't burn the limit on 120 frames.
4. **Content-Type** — auto-detected from file extension. Allowed: `.webp`, `.jpg`, `.jpeg`, `.png`, `.gif`, `.pdf`, `.mp4`, `.webm`, `.mov`. Other extensions are rejected client-side.

### Anti-patterns

- DON'T tunnel a local directory via pinggy/serveo/localhost.run and then call `media_import_from_url` against the tunnel URLs. Free tunnels inject HTML interstitials on first request → saved as `.webp` → silent scroll-sequence black frames. The 12h Antigravity #1 saga was exactly this.
- DON'T upload 120 × 1.6 MB JPG frames expecting them to "just work." Without auto-optimize, that's 192 MB — server will return 400. Flip `auto_optimize=true` (default for scroll-sequences) and Sharp compresses them to ~8 MB.
- DON'T upload to a third-party host (catbox.moe, raw.githubusercontent.com, imgur) and reference those URLs from your site. No tenant isolation, no CDN caching, eventual link rot.
- DON'T use `upload_base64` in a loop for 100+ files — the JSON-encoding overhead and the single-shot body limits make it slower than multipart. The batch endpoint is always the right choice for >1 file.

### See also

- [recipes/scroll-sequence](../SKILL.md) — for video-sourced scroll heroes (server-side frame extraction)
- [LEARNINGS.md → Media & Scroll-Sequences](../SKILL.md) — gotchas
- [SpiderIQ `/content/help` → `upload_many_local_files`](https://spideriq.ai/api/v1/content/help?format=yaml)


---

## Import From Url

Pull a file (or batch of files) **from any public URL** into the tenant's SpiderMedia R2 bucket — one MCP call. Auto-proxies Instagram / Facebook / Twitter CDN URLs that 403 direct fetches.

### When to use

- Importing an asset a client linked via Dropbox / Google Drive / WeTransfer / Notion attachment without the round-trip through local download + upload.
- Mirroring a public Instagram / Facebook / Twitter image into tenant storage so it survives the source post being deleted.
- Bulk-importing 20+ external URLs into a single folder (logo packs, brand kits, OG-image batches).
- Building an automation that ingests media references from another tool (Airtable, Sheets) into SpiderMedia.
- Pattern: "this URL has the file — put it in our bucket."

### Prerequisites

- A PAT scoped to the tenant.
- A public URL (or list of URLs) — the importer fetches server-side, so the URL must be reachable from the SpiderMedia gateway.

### Single URL

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

#### Batch

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

### Auto-proxy for social CDNs

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

### Content-type sniffing + extension

The importer:

1. Sends `HEAD` first to read `Content-Type` and `Content-Length`.
2. If the URL has no extension, derives one from `Content-Type` (`image/png` → `.png`, `video/mp4` → `.mp4`).
3. If the URL has a wrong extension (`.jpg` for an `image/webp`), the **URL extension wins** in the saved filename — but `content_type` in the response is the sniffed truth. Audit when this matters for client-side rendering.

### Folder organisation

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

### Steps

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

### Gotchas

- **The fetch happens server-side.** The URL must be reachable from SpiderMedia's gateway (egress IPs). URLs requiring cookies / auth headers won't work — proxy via `use_proxy: true` if the CDN is on the auto-detect list, otherwise the import fails.
- **No deduplication.** Two imports of the same URL create two files (unless `filename` is identical AND folder is identical AND object-storage overwrites are enabled). Check `list_files` before bulk-importing if dedup matters.
- **Large files (>100 MB) may time out.** SpiderMedia's import has a per-request timeout; videos over 100 MB should use `upload_local_file` (chunked) instead.
- **`use_proxy: true` adds latency** (proxy fetches the URL, streams to SpiderMedia, then SpiderMedia stores). For known-clean direct-fetchable URLs, leave `use_proxy` unset.
- **Tenant storage quota is enforced.** A bulk import that would exceed the quota fails partway — check `get_media_stats` before importing large batches; see [`tighten-media-budget.md`](media.md#tighten-media-budget).
- **Imports DON'T trigger image optimization automatically** — the file lands as-is. For WebP conversion / resize, post-process via separate tooling.

### Verify

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

### Anti-patterns

- **Importing the same URL 20× into a loop** because dedup isn't automatic. Check `list_files` first or use the `filename` override + a known stable name.
- **Importing huge videos (>500 MB) via `import_from_url`.** Use `upload_local_file` (chunked, resumable) for large videos.
- **Bypassing folder organisation** — `folder: ""` means root. Six months later you have 400 files at root and no way to find anything.
- **Importing user-supplied URLs without validation.** A malicious URL could point at an internal-network address if SpiderMedia's gateway egresses near it. Always validate the URL scheme + host against an allowlist for user-facing flows.
- **Trusting the file extension in the URL.** Sniff `content_type` from the response — a `.jpg` URL can be serving WebP. Some image renderers care.

### Verify the recipe → tool

```bash
./scripts/find-tool-for-intent.sh "import a file from a URL into SpiderMedia"
# Top-1 should be: recipes/media/import-from-url.md
```

### See also

- [`bulk-upload.md`](media.md#bulk-upload) — upload from local files (uses `upload_local_file` / `upload_local_directory`)
- [`tighten-media-budget.md`](media.md#tighten-media-budget) — check quota + delete unused before importing a large batch
- [`../marketplace/pick-bg-video.md`](marketplace.md#pick-bg-video) — when the asset is a curated marketplace bg-video, NOT a URL import
- [`../content/scroll-video-hero.md`](content.md#scroll-video-hero) — chains an `import_from_url` (video) → `video_to_scroll_sequence` for cinematic heroes
- [`../reference/tool-surface.md`](tool-surface.md) — the media tool family + `@spideriq/mcp` vs `@spideriq/mcp-publish` (media tools are in both)


---

## Tighten Media Budget

Find what's eating the tenant's SpiderMedia storage and delete orphaned / unused files — without yanking anything that's still referenced by a page. Three tools: `get_media_stats`, `list_files`, `delete_file`.

### When to use

- The tenant is bumping its storage quota.
- After a large campaign — purging the staging / proofs folders that are no longer referenced.
- Pre-cutover hygiene before a domain migration.
- Yearly audit: how much of the bucket is still load-bearing vs cruft.
- Pattern: "What's in the bucket? What's safe to drop?"

### Prerequisites

- A PAT scoped to the tenant.
- For destructive deletes: ideally a list of pages so you can audit references first.

### Step 1 — Read the current usage

```
get_media_stats()
# → {
#     file_count: 1247,
#     storage_used_bytes: 3_842_119_104,    # ~3.6 GB
#     storage_used_human: "3.58 GB",
#     by_type: {
#       image: { count: 980, bytes: 1_500_000_000 },
#       video: { count: 22,  bytes: 2_200_000_000 },
#       document: { count: 245, bytes: 142_000_000 }
#     },
#     quota_bytes: 5_368_709_120,            # 5 GB
#     quota_percent: 71.6
#   }
```

Quota varies per plan. The `quota_percent` is your headline metric — anything over 80% deserves a sweep; over 95% is firefighting.

### Step 2 — Find candidates for deletion

`list_files` is paginated; combine with `type` to target the biggest category first.

```
# Biggest single category from the stats above is video — start there
list_files({ type: "video", limit: 50 })
# → [
#     { key: "campaigns/2024-old/hero.mp4", size: 187_000_000, content_type: "video/mp4", uploaded_at: "..." },
#     ...
#   ]
```

| Type | Filter | Why audit first |
|---|---|---|
| `video` | Few files, big each — best ROI | One stale 200 MB video frees more than 1000 thumbnails |
| `image` | Many files, varied — slowest sweep | Look for `staging/`, `proofs/`, `temp/` folder prefixes |
| `document` | PDFs / DOCXs — often stale | Client RFPs from past quarters rarely referenced after |

#### Orphan detection — "what is no longer used"

There's no built-in `find_orphans` tool — you cross-reference manually:

```
# Pull all pages + grab every media URL referenced in blocks[]
content_list_pages({ limit: 500 })  →  for each:
content_get_page({ page_id })       →  collect URLs from blocks[].props, .data, .image_url, .video_url, .background_image, ...

# Pull all bg-video catalog URLs (these are NEVER tenant-stored; safe to ignore)
content_list_marketplace_bg_videos({ limit: 200 })

# Pull all components + their default_props image URLs
content_list_components({ limit: 200 })  →  for each:
content_get_component_by_slug({ slug })  →  inspect default_props for image/video URLs

# Then diff against list_files response
orphans = files - referenced_urls
```

This is best done as a script — keep one in `scripts/find-media-orphans.py` per-tenant if you do it often.

### Step 3 — Delete (one at a time)

```
delete_file({ key: "campaigns/2024-old/hero.mp4" })
# → { success: true, message: "File \"campaigns/2024-old/hero.mp4\" deleted" }
```

**`delete_file` is NOT gated** — there's no dry_run. Once you call it, the file is gone from R2 (R2 has soft-delete for ~7 days per the bucket policy, but the public URL 404s immediately). Always confirm the key + audit references first.

#### Bulk delete pattern

There's no `delete_files` plural — loop carefully:

```
for key in confirmed_orphans:
    delete_file({ key })
    # log success + size freed
```

Cap the loop at ~50 per session to keep individual ops auditable; for thousand-file purges, do it in batches with explicit progress logging.

### Steps — full sweep flow

```
1. get_media_stats()                                — establish baseline + identify biggest category
2. list_files({ type: <biggest> })                  — enumerate candidates
3. (cross-reference against content_list_pages + content_list_components)
4. (build a list of confirmed orphans)
5. for each orphan: delete_file({ key })
6. get_media_stats()                                — confirm new usage is below threshold
```

### Tenant quota respect

| Quota usage | Recommendation |
|---|---|
| < 50% | No action |
| 50-80% | Audit annually |
| 80-95% | Sweep this quarter; defer large new uploads |
| > 95% | Sweep NOW; new uploads will start failing |

When approaching quota, prefer **deleting** over **upgrading** — a tenant with 4 GB of 2024 RFP PDFs likely doesn't need a quota bump, just a cleanup.

### Gotchas

- **`delete_file` is irreversible from the API's perspective.** R2 lifecycle policy keeps a soft-delete window (~7 days), but the public CDN URL 404s instantly. Pages still referencing the URL render broken images until a manual restore.
- **Orphan detection misses references inside `js`/`css` blob fields of components.** A component's `js` field might hardcode an image URL — string-grep components' bodies if you're sweeping aggressively.
- **Marketplace bg-video URLs aren't tenant files** — they're served from `cdn.spideriq.ai/marketplace-bg-videos/...`. Don't try to delete them via `delete_file({ key })`; you'd get 404 (the file isn't in YOUR bucket).
- **Per-image quota matters for some plans** — `quota_bytes` from `get_media_stats` is the overall cap; a per-image-size cap (e.g. "no single file > 50 MB") may apply silently at upload time.
- **`list_files` paginates** — `limit: 20` default; `limit: 100` is the max safe ceiling. For a full sweep, page through with `offset` incrementing.

### Verify

```
get_media_stats()
# → confirm storage_used_bytes dropped by the expected amount

list_files({ type: "video", limit: 50 })
# → confirm the deleted keys are gone

# Cross-check: visit a page that USED to use the deleted file
content_visual_check({ page_url: "https://<tenant>/<page>", viewport: "desktop" })
# → should show working image (because you only deleted ORPHANS, right?)
```

### Anti-patterns

- **Deleting based on filename alone** without cross-referencing pages + components. A file named "old-hero.jpg" might still be the live hero on the about page. Always audit references first.
- **Looping `delete_file` against ALL files in a folder** without orphan detection. Folders like `marketing-2026/` may still be load-bearing.
- **Running the sweep on production tenants without a dry-run script.** Build the orphan list FIRST, log it, eyeball it, THEN loop the deletes. No "execute as you go."
- **Trusting the 7-day soft delete to bail you out.** It bails out STORAGE, not the public URL — pages render broken until restore. And restore requires CF/R2 console access; not a self-service flow.
- **Sweeping aggressively the day before a marketing launch.** New campaigns reference assets in unexpected places (OG images, email-embedded images via SpiderMail). Sweep during quiet weeks.

### Verify the recipe → tool

```bash
./scripts/find-tool-for-intent.sh "delete unused media from SpiderMedia"
# Top-1 should be: recipes/media/tighten-media-budget.md
```

### See also

- [`bulk-upload.md`](media.md#bulk-upload) — for uploading; pair with this recipe for "delete old, upload new" cycles
- [`import-from-url.md`](media.md#import-from-url) — check quota BEFORE bulk imports
- [`../content/export-page-roundtrip.md`](content.md#export-page-roundtrip) — get a list of all media URLs referenced by one page (handy for orphan detection)
- [`../audit/audit-and-fix.md`](audit.md#audit-and-fix) — broader audit suite; link-audit catches broken image URLs after deletions
- [`../reference/tool-surface.md`](tool-surface.md) — the media tool family
