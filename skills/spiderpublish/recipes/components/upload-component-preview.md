# recipes/components/upload-component-preview

Upload a preview thumbnail (PNG/JPG/GIF/WEBP/MP4) for a component — reads the file from disk, uploads to R2, auto-PATCHes `preview_thumbnail_url`. The marketplace card art for component browsers.

## When to use

- You just authored a component and want to give it card art for the marketplace browser.
- You're improving discoverability — a component without a preview thumbnail is hard to find in a UI grid.
- You're rotating a thumbnail (rebrand, new screenshot).
- You're adding animated previews (MP4 loops showing the component's behaviour over time).

If you only need a static URL pointed at an already-uploaded image → just `content_update_component({ thumbnail_url: "https://..." })`. This recipe is for when the file is on your disk and you want one-call upload + PATCH.

## Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` (exit 0 = safe).
2. **Component exists** (got `component_id` from `content_create_component` or `content_get_component_by_slug`).
3. **File on disk, ≤5 MB.** Allowed extensions: `png`, `jpg`, `jpeg`, `gif`, `webp`, `mp4`. Server enforces the 5 MB cap.
4. **You own (or have edit access to) the component.** Global components (`is_global: true`) need super_admin / marketplace-authoring-brand PAT.

## The 1-call path

```
content_upload_component_preview({
  component_id: "comp_...",
  local_path:   "./design/component-previews/sys-pretty-card.png"
})
// → {
//   success: true,
//   component_id: "comp_...",
//   url: "https://media.cdn.spideriq.ai/component-previews/<key>.png",
//   key: "component-previews/<key>.png",
//   size_bytes: 84221,
//   content_type: "image/png",
//   preview_thumbnail_url: "https://media.cdn.spideriq.ai/component-previews/<key>.png"
// }
```

That's it. The tool:
1. Reads the file from disk.
2. Sniffs content-type from extension (overrideable with `ext`).
3. POSTs multipart to `/content/components/{id}/upload-preview`.
4. Server uploads to R2.
5. Server PATCHes the component's `preview_thumbnail_url` to the R2 URL.
6. Returns the new URL.

One round-trip; no separate upload-then-patch.

## Params

| Field | Notes |
|---|---|
| `component_id` | REQUIRED. UUID from `content_create_component`. |
| `local_path` | REQUIRED. Absolute path or cwd-relative. Tool resolves; file must be readable. |
| `ext` | OPTIONAL. Override the extension/content-type. Default: extension from `local_path`. One of: `png`, `jpg`, `jpeg`, `gif`, `webp`, `mp4`. |
| `workspace` | OPTIONAL. Workspace name (default `"default"`). |

## File size + format constraints

| Format | Use for |
|---|---|
| **PNG** | Logos, icons, UI screenshots with transparency. Lossless. |
| **JPG/JPEG** | Photos, full-page screenshots. Lossy but smaller. |
| **WEBP** | Same shape as JPG but ~30% smaller. Preferred for thumbnails when supported. |
| **GIF** | Short animations (looping). Larger than equivalent MP4. |
| **MP4** | Animated previews. The CRO catalog uses MP4 to show behaviour (popup fires, bar slides in). |

5 MB cap is server-enforced. For animated MP4 over 5 MB:
- Compress more (try CRF 28-30 with H.264).
- OR use SpiderMedia upload directly (`upload_local_file`) and PATCH `preview_thumbnail_url` manually with the returned URL.

## Typical use — Tier 1-3 component preview

After authoring a component ([`create-component.md`](create-component.md)):

```
# 1. Create the component
content_create_component({
  slug: "sys-pretty-card",
  name: "Pretty card",
  html_template: "<div>...</div>",
  css: "...",
  props_schema: { ... }
})
# → { id: "comp_..." }

# 2. Take a screenshot of the rendered component (use the dashboard's preview pane, or render locally)

# 3. Upload the preview
content_upload_component_preview({
  component_id: "comp_...",
  local_path:   "./previews/sys-pretty-card.png"
})
# → component now has preview_thumbnail_url

# 4. (For marketplace components) set additional marketplace metadata
content_update_component({
  component_id: "comp_...",
  marketplace_category: "custom",
  marketplace_featured: false,
  marketplace_description: "A pretty content card with optional CTA",
  authoring_hints: {
    preferred_path: "Pass title + body via props; optional cta object",
    must_set: ["title", "body"]
  }
})

# 5. Publish (so it appears in marketplace browsers)
content_publish_component({ component_id: "comp_..." })
content_publish_component({ component_id: "comp_...", confirm_token })
```

## Animated MP4 previews (the CRO pattern)

CRO components animate their behaviour for discovery. A static thumbnail of `sys-popup-exit-intent` is just "a popup card"; an MP4 shows the modal sliding in when the cursor leaves.

To author an animated MP4 preview:

1. Record the component in action (browser, screen recorder, OBS, etc.).
2. Trim to 3-6 seconds. Loop-friendly first/last frame.
3. Encode H.264 / web-compatible MP4 at 720p or smaller. Aim for <3 MB.
4. Upload:

```
content_upload_component_preview({
  component_id: "comp_...",
  local_path:   "./previews/sys-popup-exit-intent.mp4",
  ext:          "mp4"
})
```

The marketplace browser detects MP4 and auto-loops/auto-mutes the playback. Visitors hover/scroll to the card; the preview plays.

## Replace an existing preview

Same call, new file:

```
content_upload_component_preview({
  component_id: "comp_...",
  local_path:   "./previews/sys-pretty-card-v2.png"
})
# → preview_thumbnail_url is now the new R2 URL
```

The old preview file stays in R2 (not auto-deleted; no orphan cleanup yet). If you need to remove it: SpiderMedia's `delete_file({ key })` with the old key from the prior response.

## Remove a preview entirely

There's no first-party "delete preview" tool today. Two options:

1. **Re-PATCH `preview_thumbnail_url` to `null`** via `content_update_component({ component_id, thumbnail_url: null })`.
2. **Upload a placeholder** (a transparent 1x1 PNG or a "no preview available" image) to keep visual consistency in the marketplace browser.

Option 1 lands a card without a thumbnail (the browser usually renders a generic placeholder). Option 2 keeps the card visually consistent.

## Verify

Open the marketplace browser (dashboard's marketplace page) and find your component — the new thumbnail should render. OR:

```
content_get_component_by_slug({ slug: "sys-pretty-card" })
# Check preview_thumbnail_url is the new R2 URL.
```

Visit the URL directly to confirm the file uploaded:

```bash
curl -I https://media.cdn.spideriq.ai/component-previews/<key>.png
# HTTP/2 200, content-type: image/png
```

## Anti-patterns

1. **File >5 MB.** Server-rejected. Compress or use SpiderMedia direct upload + manual PATCH.
2. **Wrong extension.** `local_path: "./preview.heic"` → not in allowlist → 422. Convert to PNG/JPG first.
3. **Forgetting to set `marketplace_*` fields** when publishing a component to the marketplace. The preview shows but other browse filters (`marketplace_category`, `is_featured`, `marketplace_description`) won't surface it. See [`../marketplace/browse-cro-components.md`](../marketplace/browse-cro-components.md).
4. **Animated MP4 longer than 8s or larger than 3 MB.** Marketplace browser auto-plays — long clips eat bandwidth, large files slow the page. Aim for 3-6s, ≤3 MB.
5. **Static screenshot of a CRO component that's all about animation.** Visitors don't get the behavioural signal. Use MP4 for animated/triggered components.
6. **Uploading a preview for a draft component thinking it'll go live with the next publish.** Preview thumbnail is independent of component status — it's updated immediately. Publishing the component just flips status; the preview is already in place.

## See also

- [`create-component.md`](create-component.md) — author the component before adding preview
- [`find-component.md`](find-component.md) — `content_get_component_by_slug` to confirm preview persisted
- [`../marketplace/browse-cro-components.md`](../marketplace/browse-cro-components.md) — where the previews surface
- [`../marketplace/author-bg-video.md`](../marketplace/author-bg-video.md) — similar pattern for bg-video assets
- [`../reference/tool-surface.md`](../reference/tool-surface.md) — `content_upload_component_preview` signature
- catalog/CLAUDE.md → Marketplace Admin Slice 1 — the upload endpoint shipped 2026-04-28
