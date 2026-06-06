# The media catalog is read-only discovery — and "empty" is normal

*Starting point, not ground truth — verify against current behaviour.*

## What it is

`spideriq-media-catalog` exposes the per-tenant `media_assets` DAM catalog
(SpiderMedia Phase 0.1 read service + Phase 1.1 public API). The catalog is the
**index** of media a tenant already has — populated by a one-time Phase 0
backfill of production data and kept current by a **non-blocking forward-sync
hook** on ingest. The skill surfaces three reads: `listAssets`, `searchAssets`,
`getAsset`.

## Why it does not write

The catalog is deliberately additive and observational over the existing
SpiderMedia backbone (SeaweedFS canonical store + Cloudflare R2 referenced tier
+ PeerTube for video). Existing producers — worker uploads, the content
pipeline, Forms — write *into* the substrate; the catalog only **reflects** them.
Uploading, transforming, or deleting media is a different surface (the
SpiderPublish content tools). Keeping this skill read-only means it can never
corrupt or race the producers — a hard backward-compatibility guarantee of the
SpiderMedia build.

## "Empty" is a normal answer

A tenant with no ingested media (or none matching a filter) gets
`{ count: 0, assets: [] }`. That is a completed read, not an error and not a
misconfiguration. Don't retry it as if it failed; report "no matching assets."

## Three ids that are easy to confuse

- `id` — the **catalog UUID**. This is what `getAsset` takes.
- `peertube_uuid` — the PeerTube short-uuid for a video asset (a separate column).
- job ids — from the job/worker pipeline; unrelated to catalog rows.

Using a `peertube_uuid` or a job id where a catalog `id` is expected returns 404.

## Tag logic differs by method

`listAssets` filters tags with **AND** (all must match); `searchAssets` matches
with **ANY** (overlap). Same param name, opposite semantics — the single most
common surprise. See `references/search.md`.
