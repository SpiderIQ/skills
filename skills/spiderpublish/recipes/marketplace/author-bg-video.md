# recipes/marketplace/author-bg-video

Publish a curated background-video clip to the marketplace bg-video catalog. Super-admin / marketplace-authoring-brand operation. Visitors pair the clip with a `sys-bg-video` component for hero / section backgrounds.

## When to use

- You're on the SpiderIQ team adding clips to the bg-video gallery.
- A new clip is ready (MP4 ≤50 MB, with a JPG/PNG poster fallback for autoplay-blocked viewers).
- You're rotating the featured set or marking some clips deprecated.

If you want to USE an existing bg-video on a page → use the `sys-bg-video` component via `page_insert_section` (see [`browse-cro-components.md`](browse-cro-components.md)). If you're authoring a site template → [`author-site-template.md`](author-site-template.md).

## Prerequisites

1. **PAT scope is super_admin OR brand_admin of `cli_spideriq_templates`.** Other PATs 403 on the create endpoint.
2. **MP4 file ≤50 MB.** Compressed; H.264 encoding; web-compatible.
3. **JPG/PNG poster image.** Used as fallback when autoplay is blocked (mobile Safari, data-saver, low-power mode).
4. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh`; bound to the authoring tenant.

## The 4-call path

```
1. content_upload_bg_video       — upload MP4 to R2
2. content_upload_bg_video       — upload poster JPG (same tool, different file)
3. (REST) POST /content/bg-videos — create the catalog row                   # VERIFY tool name
4. content_get_marketplace_bg_video — confirm shape
```

<!-- VERIFY: confirm `content_create_bg_video` / `content_update_bg_video` MCP tool surface. The upload tool exists (`content_upload_bg_video`); the catalog-row CRUD may be REST-only via `POST /api/v1/dashboard/projects/{pid}/content/bg-videos` until MCP wrapper lands. Grep `packages/mcp-tools/src/publish/` for `bg_video_create`. -->

### Step 1 — upload the MP4

```
content_upload_bg_video({
  slug:       "ocean-sunrise-loop",         # R2 key stem: bg-videos/ocean-sunrise-loop.mp4
  local_path: "./bg-videos/ocean-sunrise.mp4"
})
// → {
//   url:          "https://media.cdn.spideriq.ai/bg-videos/ocean-sunrise-loop.mp4",
//   key:          "bg-videos/ocean-sunrise-loop.mp4",
//   size_bytes:   24_315_881,
//   content_type: "video/mp4"
// }
```

50 MB server-enforced cap. Tool sniffs content-type from `.mp4` extension.

**For 3-8 second background loops:**

| Setting | Target |
|---|---|
| Duration | 3-8 seconds (longer = more bandwidth, no behavioural benefit) |
| Resolution | 1920×1080 (downscales fine on mobile) |
| Codec | H.264 baseline / main profile |
| Bitrate | 2-5 Mbps |
| File size | <5 MB ideally; ≤50 MB hard cap |
| Audio | NONE (autoplay requires muted; remove audio track) |

Recommended encode command:
```bash
ffmpeg -i input.mov \
  -c:v libx264 -profile:v main -preset slow -crf 23 \
  -vf "scale=1920:-2,fps=24" \
  -an \                                     # drop audio
  -movflags +faststart \                    # web-optimized
  -t 6 \                                    # trim to 6s
  output.mp4
```

### Step 2 — upload the poster

```
content_upload_bg_video({
  slug:       "ocean-sunrise-loop",         # SAME slug — overwrites R2 key with different extension
  local_path: "./bg-videos/ocean-sunrise-poster.jpg",
  ext:        "jpg"
})
// → { url: "https://media.cdn.spideriq.ai/bg-videos/ocean-sunrise-loop.jpg", ... }
```

The poster IS the first/representative frame of the video, used when autoplay is blocked (mobile Safari / data-saver / low-power mode). Without a poster, viewers see a black box instead.

Same `slug` — R2 key differs by extension. The catalog row references BOTH URLs.

### Step 3 — create the catalog row

REST until MCP wrapper lands. <!-- VERIFY: prefer MCP if `content_create_bg_video` exists. -->

```bash
curl -X POST "https://spideriq.ai/api/v1/dashboard/projects/$AUTHORING_PID/content/bg-videos" \
  -H "Authorization: Bearer $CLIENT_ID:$API_KEY:$API_SECRET" \
  -H "Content-Type: application/json" \
  -d '{
    "slug":             "ocean-sunrise-loop",
    "name":             "Ocean sunrise — calm loop",
    "description":      "Wide aerial of ocean at sunrise. Calm waves; warm orange palette. Perfect for hotel / spa / wellness heros.",
    "video_url":        "https://media.cdn.spideriq.ai/bg-videos/ocean-sunrise-loop.mp4",
    "poster_url":       "https://media.cdn.spideriq.ai/bg-videos/ocean-sunrise-loop.jpg",
    "category":         "nature",
    "duration_seconds": 6,
    "loop_seconds":     6,
    "tags":             ["ocean", "sunrise", "calm", "warm", "aerial"],
    "is_featured":      false,
    "replication_prompt": "Aerial drone footage of ocean at sunrise, warm orange palette, calm waves, slow camera pan. No people, no objects.",
    "agent_meta": {
      "mood":           "calm",
      "palette":        "warm",
      "brand_fit_tags": ["hotel", "spa", "wellness"],
      "scene_type":     "hero-bg-video"
    }
  }'
# → 201 Created
```

| Field | Notes |
|---|---|
| `slug` | URL-safe identifier. Stable handle. |
| `name` | Display name in the marketplace browser. |
| `description` | Markdown-allowed. |
| `video_url` | R2 URL from Step 1 (MP4). Strict-allowlisted to R2 hosts post-2026-05-12. |
| `poster_url` | R2 URL from Step 2 (poster image). Same allowlist. |
| `category` | One of: `nature | city | abstract | food | tech | people`. The 6 catalog dimensions. |
| `duration_seconds` | Real duration. Used by the renderer to set `<video duration>`. |
| `loop_seconds` | Loop point — typically equals duration. Lets the renderer fade-cut at a clean boundary. |
| `tags[]` | Free-form. Surfaces in `content_list_marketplace_bg_videos({ tag })`. |
| `is_featured` | Promote in the catalog. Curated decision. |
| `replication_prompt` | TEXT-TO-VIDEO prompt that would produce this clip. For Sora/Veo/Runway agents to remix. Optional but high-leverage. |
| `agent_meta.{mood, palette, brand_fit_tags, scene_type}` | AI-discovery axes for `marketplace_search`. ALWAYS set. |

### Step 4 — confirm + smoke

```
content_get_marketplace_bg_video({ slug: "ocean-sunrise-loop" })
# → full record
```

Smoke-test in a test tenant by pairing with `sys-bg-video`:

```
# In a test tenant
page_insert_section({
  page_id:        "<test-page>",
  component_slug: "sys-bg-video",
  props: {
    video_url:  "https://media.cdn.spideriq.ai/bg-videos/ocean-sunrise-loop.mp4",
    poster_url: "https://media.cdn.spideriq.ai/bg-videos/ocean-sunrise-loop.jpg",
    overlay_opacity: 0.3,
    headline:   "Welcome"
  }
})
```

Deploy, visual-check:

```
content_visual_check({ page_url: "https://<test-tenant>/", viewport: "desktop" })
# Check screenshot shows the hero with poster (first frame) visible.
```

Open in an actual browser to see the loop play (visual-check captures the first paint; doesn't wait for video playback).

## Update / rotate

To replace the MP4 (e.g. better-encoded version):

```
content_upload_bg_video({ slug: "ocean-sunrise-loop", local_path: "./v2/ocean-sunrise.mp4" })
# Same R2 key, overwrites
```

R2 overwrites are atomic; visitors stop seeing the old version on next cache TTL.

To deprecate a clip:

```bash
# PATCH the catalog row
curl -X PATCH "https://spideriq.ai/api/v1/dashboard/projects/$AUTHORING_PID/content/bg-videos/<slug>" \
  -H "Authorization: Bearer ..." \
  -d '{ "is_featured": false, "tags": ["deprecated", ...] }'
```

There's no "delete" today; un-feature + add deprecated tag is the soft path. Hard delete via REST `DELETE /content/bg-videos/<slug>` exists but breaks any tenant currently using the slug.

## Anti-patterns

1. **Uploading with audio track intact.** Autoplay requires `muted` to fire (browser policy). With audio, autoplay silently fails on most browsers. ALWAYS strip audio in encoding (`-an` flag).
2. **Skipping the poster.** Mobile Safari + data-saver viewers see a black box. ALWAYS upload + reference a poster.
3. **MP4 > 5 MB for a 6-second clip.** Visitors pay the bandwidth on every page load. Compress harder (CRF 25-28; lower resolution; shorter duration).
4. **Forgetting `agent_meta`.** `marketplace_search` is the high-leverage discovery surface. Without `mood` / `palette` / `scene_type`, agents looking for "calm ocean for a spa site" won't find your clip.
5. **Authoring in a customer tenant.** Always `cli_spideriq_templates` for marketplace-authored assets.
6. **Setting `is_featured: true` on your own upload.** Curation decision — leave to the SpiderIQ team based on quality + downstream usage.
7. **Reusing a slug across categories.** Slugs are unique. `ocean-sunrise-loop` in category `nature` can't also exist in `abstract`. Different slug per asset.

## See also

- [`browse-cro-components.md`](browse-cro-components.md) — `sys-bg-video` component that consumes bg-videos
- [`author-site-template.md`](author-site-template.md) — sibling marketplace authoring pattern (site templates instead of bg-videos)
- [`pick-bg-video.md`](#) — downstream: a tenant browses + picks a bg-video (queued v0.5.0)
- [`suggest-agent-meta.md`](suggest-agent-meta.md) — LLM-suggest the agent_meta axes
- [`../reference/tool-surface.md`](../reference/tool-surface.md) — `content_*_bg_video` tool catalog
- catalog/CLAUDE.md → "Marketplace Admin Slice 1" — backend internals
