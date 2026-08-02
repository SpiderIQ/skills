## spideriq-media-catalog

Read-only discovery over the per-tenant SpiderMedia DAM catalog. 3 tool calls — list/filter, search, and read one asset.

### What this skill does

- **Browse + filter** — `listAssets` returns assets newest-first; narrow by `kind` (image/video/doc), exact `folder`, `tags` (ALL must match), `status`, `storage_tier`. Paginate with `limit`/`offset`.
- **Search** — `searchAssets`: `q` substring-matches the asset key/folder (case-insensitive), `tags` is ANY-overlap, `kind` narrows. (Note the deliberate AND-vs-ANY difference from `listAssets`.)
- **Read one asset** — `getAsset(asset_id)` returns the full metadata row by catalog id: storage tier, key, bucket/peertube_uuid, mime, dimensions, duration, folder, tags, metadata, provenance, timestamps.

### Typical workflows

- **Find-before-create** — search the catalog for an existing hero image / product video before generating a new one.
- **Content audit** — list every `kind=video status=ready` asset, or everything in a given folder.
- **Pipeline confirmation** — after a scrape/upload, list newest assets to confirm what landed.

### Auth + isolation

Per-brand scoping is enforced server-side via the PAT — there is no flag to escape the active brand's catalog. Read-only: no upload/transform/delete. Asset ids are catalog UUIDs (not job ids, not `peertube_uuid`).
