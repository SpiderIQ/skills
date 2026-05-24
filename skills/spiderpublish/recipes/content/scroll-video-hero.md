# recipes/scroll-sequence

Cinematic scroll-scrubbed hero from a source video — **one tool call**.

## The one-shot path (preferred, v2.87.0+)

```
video_to_scroll_sequence(
  video_url = "https://media.cdn.spideriq.ai/.../hero.mp4",
  page_slug = "home"
)
```

That single MCP call runs the whole pipeline server-side:
1. Submits `extract_frames` against the video (ffmpeg, WebP, ~7× smaller than JPEG).
2. Polls to completion.
3. Inserts a `sys-scroll-sequence` component block into the target page **as a draft**.
4. Returns `{manifest, block, page}` including the new version ID.

Then, because the block lands as a draft (never auto-publishes):
```
content_deploy_site_preview()        → review at preview-XXX.sites.spideriq.ai
content_deploy_site_production(confirm_token)
```

### Common variants

```
# Custom frame count + longer scroll distance
video_to_scroll_sequence(
  video_url="...", page_slug="home",
  target_frames=180,
  scroll_distance_vh=600,
)

# FPS-based sampling instead of exact count
video_to_scroll_sequence(
  video_url="...", page_slug="home",
  strategy="fps", fps=24,
)

# Insert before an existing hero block instead of appending
video_to_scroll_sequence(
  video_url="...", page_slug="home",
  position={"before": "hero-gradient"},
)

# Just want the block JSON, don't touch the page yet
video_to_scroll_sequence(
  video_url="...", page_slug="home",
  dry_run=true,
)
```

## Two input shapes (v1.1.0+)

The `sys-scroll-sequence` component accepts **either** of these prop shapes:

### Shape A — `{base_url, pattern, count}` (preferred)

```json
{
  "type": "component",
  "component_slug": "sys-scroll-sequence",
  "props": {
    "base_url": "https://media.spideriq.ai/client-xxx/content/scroll-sequences/<job_id>",
    "pattern": "frame_{0001..0120}.webp",
    "count": 120,
    "scroll_distance_vh": 400,
    "preload_strategy": "progressive"
  }
}
```

This is what `video_to_scroll_sequence` produces. Tiny prop footprint (~20 bytes of URLs), component expands them at render time. **Use this whenever frames come from `extract_frames`.**

### Shape B — `{image_urls[]}` (v1.1.0, for hand-picked URLs)

```json
{
  "type": "component",
  "component_slug": "sys-scroll-sequence",
  "props": {
    "image_urls": [
      "https://cdn.example.com/hero/frame_001.webp",
      "https://cdn.example.com/hero/frame_002.webp",
      "..."
    ],
    "scroll_distance_vh": 400,
    "preload_strategy": "progressive"
  }
}
```

Use when frames live on multiple hosts, have non-numeric names, or come from a legacy CDN that doesn't fit a URL pattern. Heavier (all URLs stored inline, up to 600), but unconstrained.

The component's `oneOf` schema rejects mixing both shapes in the same block.

## The legacy 5-step recipe (fallback — still works)

If your MCP server is older than v2.87.0 (no `video_to_scroll_sequence` tool) or you need to split the steps for a custom flow:

1. **Reference a source video** — must be a public URL (SpiderMedia or di-atomic preferred).
   Tool: `upload_file` / `media_import_from_url` if the video isn't already hosted.

2. **Submit `extract_frames` job.**
   Tool: `submit_job(type="spiderVideo", payload={action:"extract_frames", ...})`.
   Params:
   - `video_url` — the mp4 URL
   - `strategy` — `"target_frames"` (default 120), `"fps"`, or `"duration_fps"`
   - `output_format` — `"webp"` (recommended)

3. **Poll until completion.**
   Tool: `get_job_results(job_id)` → `status == "completed"` → manifest at `data.manifest = {base_url, pattern, count}`.

4. **Insert the `sys-scroll-sequence` block into a page.**
   Tool: `content_create_page` / `content_update_page`.
   ```json
   {
     "type": "component",
     "component_slug": "sys-scroll-sequence",
     "props": {
       "base_url": "<from manifest>",
       "pattern":  "<from manifest>",
       "count":    <from manifest>,
       "scroll_distance_vh": 400,
       "preload_strategy": "progressive"
     }
   }
   ```

5. **Deploy.**
   `content_deploy_site_preview` → verify → `content_deploy_site_production(confirm_token)`.

The one-shot call just bundles steps 2–4 into a single API call. Step 1 stays explicit (you decide where the source lives), and step 5 stays explicit (preview + confirm_token gate).

## Why not hand-roll your own frames?

- `sys-scroll-sequence` is Tier 3 (GSAP + ScrollTrigger) and handles canvas setup, sticky positioning, progressive preload (±15 frame window) — so your component stays ~2 KB of JS instead of 14 KB.
- Hardcoding 100+ URLs in a custom component triggers CDN rate-limit drops → black-frame "flashlight strobe" during scroll.
- Tier 3 CDN deps are deduplicated globally — your page doesn't pay the GSAP load cost twice.

## Recommended frame counts

| Scroll section length | Frames | Strategy |
|---|---|---|
| Short hero (~400 vh) | 90–120 | `target_frames=120` |
| Medium hero (~600 vh) | 120–180 | `target_frames=150` |
| Long cinematic (1000 vh+) | 180–240 | `target_frames=200` |

Above 240 frames: split into two sequences or use a real `<video>` element.

## Files in this skill

- `SKILL.md` — this file (human-readable recipe)
- `schema.yaml` — Tier 2 tool-sequence (one-shot + legacy 5-step)
- `impl.ts` — Tier 3 self-contained TypeScript against `@spideriq/core`

## See also

- [AGENTS.md → Scroll-Linked Hero](../../../AGENTS.md#scroll-linked-hero-image-sequence--use-sys-scroll-sequence)
- [LEARNINGS.md → Media & Scroll-Sequences](../../../LEARNINGS.md#media--scroll-sequences)
- [examples/scroll-sequence.sh](../../../examples/scroll-sequence.sh) — runnable bash version
- [components/scroll-sequence.json](../../../components/scroll-sequence.json) — block-config reference
