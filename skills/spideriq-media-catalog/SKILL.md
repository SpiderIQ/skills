---
name: spideriq-media-catalog
description: >
  Browse and search a tenant's SpiderMedia asset catalog (DAM) — the read-only
  discovery layer over every image, video, and doc already ingested across
  SeaweedFS, Cloudflare R2, and PeerTube. List assets newest-first with
  kind/folder/tags/status/storage-tier filters, fetch one asset's full metadata
  row by id, or substring-search keys and folders. Use it to answer "what media
  do I have?", "find my videos / images", "list assets in this folder", "search
  the media library". Read-only: it reflects assets the workers and content
  pipeline already produced — it does not upload, transform, or delete media.
  For uploading/managing media use the SpiderPublish content tools; for a single
  lead screenshot/photo URL use idap_media.
version: "0.1.0"
category: data-collection
---

# spideriq-media-catalog

The read-only discovery layer over SpiderMedia — a tenant's **DAM catalog** of
every asset already ingested, across three storage tiers.

```
  ┌─────────── SpiderMedia per-tenant catalog (norm_cli_<tenant>.media_assets) ───────────┐
  │  images · videos · docs        storage_tier: seaweedfs | r2 | peertube                │
  └──────────────────────────────────────────────────────────────────────────────────────┘
        listAssets ─────────────▶ page newest-first, filter kind/folder/tags(ALL)/status/tier
        searchAssets ───────────▶ q substring on key/folder + kind + tags(ANY)
        getAsset(id) ───────────▶ one asset's full metadata row
```

This skill is **read-only**. It does not create, upload, transform, or delete
media — it tells you what is already there.

## Approach

1. **Explore** — `listAssets` to page the catalog newest-first. Narrow with
   `kind` (image/video/doc), `folder`, `tags` (ALL must match), `status`, or
   `storage_tier`.
2. **Find** — `searchAssets` when you have a name fragment: `q` substring-matches
   the key/folder; `tags` here is ANY-overlap; `kind` narrows.
3. **Read** — `getAsset(asset_id)` for one asset's full row once you have its
   catalog id.

Add `?format=yaml` (or `md`) to any call — `SPIDERIQ_FORMAT=yaml` makes it the
default — for 40–76% fewer tokens.

## Rules (Non-Negotiable)

- **TENANT-SCOPED:** every call is scoped to the caller's tenant via the PAT. It
  never returns another tenant's assets — do not try to pass a tenant/client id.
- **READ-ONLY:** there is no write surface here. To upload or manage media, route
  to the SpiderPublish content tools, not this skill.
- **IDS ARE CATALOG UUIDs:** `getAsset` takes the catalog `id` field — NOT a job
  id and NOT the `peertube_uuid` (which is a separate column on the row). Passing
  the wrong id 404s.

## Decision tree — pick a method

| The user wants to… | Call | Read |
|---|---|---|
| See what media exists / page the library | `listAssets` | `references/browse-and-filter.md` |
| Narrow to a kind / folder / status / tier | `listAssets` (filters) | `references/browse-and-filter.md` |
| Find an asset by name fragment or any tag | `searchAssets` | `references/search.md` |
| Read one asset's full metadata | `getAsset` | `references/browse-and-filter.md` |

## Filter semantics (the one thing that bites)

`listAssets tags` = **AND** (an asset must carry *every* tag).
`searchAssets tags` = **ANY** (overlap — *any one* tag matches).
Same param name, opposite logic. `searchAssets q` matches the **key/folder
substring only** — not metadata, not tags. See `references/search.md`.

## Asset row shape (what every method returns per asset)

`id` (catalog UUID) · `kind` (image|video|doc) · `status`
(pending|processing|ready|failed) · `storage_tier` (seaweedfs|r2|peertube) ·
`key` · `bucket?` · `peertube_uuid?` · `mime_type?` · `size_bytes?` ·
`width?` · `height?` · `duration_s?` · `folder?` · `tags[]` · `metadata{}` ·
`source_worker?` · `created_by?` · `created_at` · `updated_at`.

## References (loaded on demand)

- `references/browse-and-filter.md` — **Always read** before listing/reading: filters, pagination, the asset row, the three storage tiers.
- `references/search.md` — search vs list, AND-vs-ANY tags, what `q` matches.

## Learnings (starting points — verify against current behaviour)

- `learnings/2026-06-06-read-only-catalog/` — why the catalog is read-only and what "empty" means.

## See also

- **SpiderPublish content tools** (`@spideriq/mcp-publish`) — to UPLOAD / manage media (this skill only reads).
- **spiderflows** — to PRODUCE media via scrapes/crawls (this skill reads the result).
- **idap_media** — to proxy a single screenshot/photo URL out of normalized lead data (a different store).
- Token economy: `?format=yaml|md` on every GET, or `SPIDERIQ_FORMAT=yaml`.
