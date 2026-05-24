# recipes/media/tighten-media-budget

Find what's eating the tenant's SpiderMedia storage and delete orphaned / unused files — without yanking anything that's still referenced by a page. Three tools: `get_media_stats`, `list_files`, `delete_file`.

## When to use

- The tenant is bumping its storage quota.
- After a large campaign — purging the staging / proofs folders that are no longer referenced.
- Pre-cutover hygiene before a domain migration.
- Yearly audit: how much of the bucket is still load-bearing vs cruft.
- Pattern: "What's in the bucket? What's safe to drop?"

## Prerequisites

- A PAT scoped to the tenant.
- For destructive deletes: ideally a list of pages so you can audit references first.

## Step 1 — Read the current usage

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

## Step 2 — Find candidates for deletion

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

### Orphan detection — "what is no longer used"

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

## Step 3 — Delete (one at a time)

```
delete_file({ key: "campaigns/2024-old/hero.mp4" })
# → { success: true, message: "File \"campaigns/2024-old/hero.mp4\" deleted" }
```

**`delete_file` is NOT gated** — there's no dry_run. Once you call it, the file is gone from R2 (R2 has soft-delete for ~7 days per the bucket policy, but the public URL 404s immediately). Always confirm the key + audit references first.

### Bulk delete pattern

There's no `delete_files` plural — loop carefully:

```
for key in confirmed_orphans:
    delete_file({ key })
    # log success + size freed
```

Cap the loop at ~50 per session to keep individual ops auditable; for thousand-file purges, do it in batches with explicit progress logging.

## Steps — full sweep flow

```
1. get_media_stats()                                — establish baseline + identify biggest category
2. list_files({ type: <biggest> })                  — enumerate candidates
3. (cross-reference against content_list_pages + content_list_components)
4. (build a list of confirmed orphans)
5. for each orphan: delete_file({ key })
6. get_media_stats()                                — confirm new usage is below threshold
```

## Tenant quota respect

| Quota usage | Recommendation |
|---|---|
| < 50% | No action |
| 50-80% | Audit annually |
| 80-95% | Sweep this quarter; defer large new uploads |
| > 95% | Sweep NOW; new uploads will start failing |

When approaching quota, prefer **deleting** over **upgrading** — a tenant with 4 GB of 2024 RFP PDFs likely doesn't need a quota bump, just a cleanup.

## Gotchas

- **`delete_file` is irreversible from the API's perspective.** R2 lifecycle policy keeps a soft-delete window (~7 days), but the public CDN URL 404s instantly. Pages still referencing the URL render broken images until a manual restore.
- **Orphan detection misses references inside `js`/`css` blob fields of components.** A component's `js` field might hardcode an image URL — string-grep components' bodies if you're sweeping aggressively.
- **Marketplace bg-video URLs aren't tenant files** — they're served from `cdn.spideriq.ai/marketplace-bg-videos/...`. Don't try to delete them via `delete_file({ key })`; you'd get 404 (the file isn't in YOUR bucket).
- **Per-image quota matters for some plans** — `quota_bytes` from `get_media_stats` is the overall cap; a per-image-size cap (e.g. "no single file > 50 MB") may apply silently at upload time.
- **`list_files` paginates** — `limit: 20` default; `limit: 100` is the max safe ceiling. For a full sweep, page through with `offset` incrementing.

## Verify

```
get_media_stats()
# → confirm storage_used_bytes dropped by the expected amount

list_files({ type: "video", limit: 50 })
# → confirm the deleted keys are gone

# Cross-check: visit a page that USED to use the deleted file
content_visual_check({ page_url: "https://<tenant>/<page>", viewport: "desktop" })
# → should show working image (because you only deleted ORPHANS, right?)
```

## Anti-patterns

- **Deleting based on filename alone** without cross-referencing pages + components. A file named "old-hero.jpg" might still be the live hero on the about page. Always audit references first.
- **Looping `delete_file` against ALL files in a folder** without orphan detection. Folders like `marketing-2026/` may still be load-bearing.
- **Running the sweep on production tenants without a dry-run script.** Build the orphan list FIRST, log it, eyeball it, THEN loop the deletes. No "execute as you go."
- **Trusting the 7-day soft delete to bail you out.** It bails out STORAGE, not the public URL — pages render broken until restore. And restore requires CF/R2 console access; not a self-service flow.
- **Sweeping aggressively the day before a marketing launch.** New campaigns reference assets in unexpected places (OG images, email-embedded images via SpiderMail). Sweep during quiet weeks.

## Verify the recipe → tool

```bash
./scripts/find-tool-for-intent.sh "delete unused media from SpiderMedia"
# Top-1 should be: recipes/media/tighten-media-budget.md
```

## See also

- [`bulk-upload.md`](bulk-upload.md) — for uploading; pair with this recipe for "delete old, upload new" cycles
- [`import-from-url.md`](import-from-url.md) — check quota BEFORE bulk imports
- [`../content/export-page-roundtrip.md`](../content/export-page-roundtrip.md) — get a list of all media URLs referenced by one page (handy for orphan detection)
- [`../audit/audit-and-fix.md`](../audit/audit-and-fix.md) — broader audit suite; link-audit catches broken image URLs after deletions
- [`../reference/tool-surface.md`](../reference/tool-surface.md) — the media tool family
