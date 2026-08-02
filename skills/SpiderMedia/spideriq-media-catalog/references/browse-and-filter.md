# Browse, filter, and read the media catalog

The everyday read path: page the catalog, narrow it, and read one asset's full row.

## Steps

1. **Page the catalog** — `listAssets` returns assets newest-first.
   - `GET /api/v1/media/catalog/assets?limit=50&offset=0`
   - Response envelope: `{ success, count, limit, offset, assets: [...] }`.
   - Page with `offset` (`offset += limit`) until `count < limit`.

2. **Narrow with filters** (all AND-combined):
   - `kind=image|video|doc`
   - `folder=<exact DAM folder path>` (exact match, not a prefix)
   - `tags=a&tags=b` — asset must carry **ALL** of these tags
   - `status=pending|processing|ready|failed`
   - `storage_tier=seaweedfs|r2|peertube`

3. **Read one asset** — `getAsset` with the catalog `id`:
   - `GET /api/v1/media/catalog/assets/{asset_id}`
   - Returns the same row shape as a list entry; `404` if the id is not in this tenant's catalog.

4. **Token-efficient output** — add `?format=yaml` or `?format=md` to any call, or set `SPIDERIQ_FORMAT=yaml`.

## The asset row

| Field | Notes |
|---|---|
| `id` | Catalog UUID — the handle for `getAsset`. |
| `kind` | `image` \| `video` \| `doc`. |
| `status` | `pending` \| `processing` \| `ready` \| `failed`. Filter to `ready` for usable assets. |
| `storage_tier` | `seaweedfs` (canonical object store) \| `r2` (Cloudflare, referenced tier) \| `peertube` (video). |
| `key` | Object key / path within the storage tier. |
| `bucket` | S3/R2 bucket; `null` for peertube. |
| `peertube_uuid` | PeerTube short-uuid for video assets — **not** the catalog `id`. |
| `mime_type`, `size_bytes`, `width`, `height`, `duration_s` | Optional dimensions (sparse on docs). |
| `folder`, `tags[]`, `metadata{}` | DAM organization + free-form JSONB. |
| `source_worker`, `created_by` | Provenance/attribution. |
| `created_at`, `updated_at` | UTC timestamps. |

## The three storage tiers

- **seaweedfs** — the canonical SeaweedFS object store (the platform-wide media backbone).
- **r2** — Cloudflare R2; a *referenced* tier (some assets live/mirror here, e.g. CDN delivery).
- **peertube** — video assets; the row carries `peertube_uuid` (the PeerTube handle).

A tenant's catalog can mix all three; `storage_tier` filters to one.

## Gotchas

- **`folder` is exact**, not a prefix — `folder=campaigns` will not match `campaigns/2026`.
- **`tags` on listAssets is AND** — every tag must be present. For "any of these tags" use `searchAssets` (see `search.md`).
- **`status` filters, it doesn't sort** — newest-first ordering is fixed; there is no `sort` param.
- **An empty `assets: []` with `count: 0` is a normal completed read** (a tenant with no ingested media of that filter), not an error.
- **`getAsset` 404** = the id isn't in *this* tenant's catalog (wrong id, wrong tenant's PAT, or a `peertube_uuid` used by mistake).

## Verify

```bash
# Newest 5 assets, YAML
curl -s -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/media/catalog/assets?limit=5&format=yaml"

# Only ready videos on the peertube tier
curl -s -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/media/catalog/assets?kind=video&status=ready&storage_tier=peertube"

# One asset's full row
curl -s -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/media/catalog/assets/<asset_id>?format=yaml"
```

A `2xx` with a JSON/YAML envelope (not an HTML login page) confirms auth + routing.
