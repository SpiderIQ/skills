# recipes/marketplace/pick-bg-video

Browse the curated background-video library (12 short loops across 6 categories) and pair the chosen clip with a `sys-bg-video` component on a page — in one preview-then-confirm flow via `page_insert_section`.

## When to use

- Adding a cinematic hero with a looping background video without sourcing/encoding/uploading your own clip.
- Building a section with a `sys-bg-video` block where you don't yet have an asset.
- Surfacing the catalog on a dashboard "browse bg videos" picker.
- Pattern: "I want one of those looping hero videos but I haven't picked which."

## Prerequisites

- A PAT scoped to the tenant.
- A target page (`page_id`) where you want to insert the section.
- The `sys-bg-video` component published in the marketplace (it is — it ships in every tenant via the global components catalog).

## Step 1 — Browse the catalog

```
content_list_marketplace_bg_videos({
  category: "nature"       # optional; one of: nature | city | abstract | food | tech | people
})
# → [
#     {
#       slug: "forest-mist-loop-12s",
#       name: "Forest mist — 12s loop",
#       description: "Slow drift through pine canopy, golden hour",
#       r2_url:     "https://cdn.spideriq.ai/marketplace-bg-videos/forest-mist-loop-12s.mp4",
#       poster_url: "https://cdn.spideriq.ai/marketplace-bg-videos/forest-mist-loop-12s-poster.webp",
#       duration_seconds: 12,
#       loop_seconds:     12,
#       category:   "nature",
#       tags:       ["forest", "golden-hour", "calm"],
#       is_featured: true
#     },
#     ...
#   ]
```

**Public read, no auth required for the browse**. Filterable by `category`, `tag`, `is_featured`. Pagination via `limit` (≤200) + `offset`.

The catalog ships with 12 clips across 6 categories:

| Category | Tone |
|---|---|
| `nature` | Forest, ocean, sky, weather — calm, organic |
| `city` | Urban motion, neon, traffic-light timelapses — energetic |
| `abstract` | Particle systems, gradient sweeps, fluid sims — modern brand |
| `food` | Steam, pour shots, ingredient drift — culinary |
| `tech` | Server racks, circuit boards, holographic UIs — B2B SaaS |
| `people` | Faceless silhouettes, hands at work — service brands |

### Inspect one clip

```
content_get_marketplace_bg_video({ slug: "forest-mist-loop-12s" })
# → the full row above (single fetch by slug; cheaper than re-filtering)
```

## Step 2 — Insert into a page with `page_insert_section`

The `sys-bg-video` component takes the chosen clip's URLs as props. Insert via Phase 11+12 gated `page_insert_section`:

```
# Stage 2a — dry_run preview
page_insert_section({
  page_id:        "<page-uuid>",
  component_slug: "sys-bg-video",
  props: {
    video_url:  "https://cdn.spideriq.ai/marketplace-bg-videos/forest-mist-loop-12s.mp4",
    poster_url: "https://cdn.spideriq.ai/marketplace-bg-videos/forest-mist-loop-12s-poster.webp",
    loop:       true,
    autoplay:   true,
    muted:      true,
    overlay_opacity: 0.4
  },
  position: "start",     # "start" | "end" | "before" | "after" | int
  dry_run:  true
})
# → {
#     dry_run: true,
#     preview: { insertion_index: 0, new_block_id: "blk_...", blocks_count_before: 5, blocks_count_after: 6 },
#     confirm_token: "cft_..."
#   }

# Stage 2b — consume the token
page_insert_section({
  page_id:        "<page-uuid>",
  component_slug: "sys-bg-video",
  props:          { ... same as above ... },
  position:       "start",
  confirm_token:  "cft_..."
})
# → { success: true, new_block_id: "blk_...", page: {...updated...} }
```

`position: "start"` puts the bg-video as the first block (the hero slot). `"before" / "after"` need an `anchor_block_id`.

The page itself is NOT republished after insert — call `content_publish_page` (safe-default gated) and then `content_deploy_site_preview` → `content_deploy_site_production` to push live.

## Steps — full flow

```
1. content_list_marketplace_bg_videos({ category: "nature" })   — browse
2. content_get_marketplace_bg_video({ slug })                    — confirm pick
3. page_insert_section({ ..., dry_run: true })                   — preview insert
4. page_insert_section({ ..., confirm_token })                   — confirm
5. content_publish_page({ page_id })                             — preview + confirm
6. content_deploy_site_preview()                                 — preview URL
7. content_deploy_site_production({ confirm_token })             — push live
8. content_visual_check({ page_url, viewport })                  — verify
```

## Recommended props by use case

| Use case | `overlay_opacity` | `autoplay` | `muted` | Notes |
|---|---|---|---|---|
| Hero with copy on top | 0.4–0.6 | true | true | Overlay needed for text contrast |
| Background ambient (footer / break) | 0.0 | true | true | No overlay; muted always |
| Click-to-play (with sound) | 0.0 | false | false | Browsers block autoplay-with-sound; needs user gesture |
| Mobile-first | 0.5 | true | true | Always muted on mobile; `playsinline` is implicit |

## Gotchas

- **`page_insert_section` is Phase 11+12 gated.** You can't skip the dry_run → confirm dance. The dry_run preview tells you the insertion index — useful when `position: "start"` and there's already a hero block.
- **`autoplay: true, muted: false` rarely works.** Browsers block autoplay with sound. Pair `autoplay: true` with `muted: true` always; offer a sound toggle as a separate UI.
- **Marketplace clips are ~5-15 MB each** — fine for a hero but adds to LCP. Run [`../audit/visual-check-a-page.md`](../audit/visual-check-a-page.md) post-deploy with `viewport: "mobile"` to confirm acceptable load time.
- **Poster image is critical for perceived performance** — without it, the section is blank until the video buffers. Always pass `poster_url` from the catalog row.
- **The catalog is curated, not user-uploadable from this tool.** To publish a NEW bg-video to the marketplace, see [`author-bg-video.md`](author-bg-video.md) (super_admin only).
- **`r2_url` may change between catalog versions** — store it in `props` at insert time; don't expect to read it dynamically.

## Verify

```
content_get_page({ page_id })
# → confirm blocks[0] has component_slug: "sys-bg-video" and your chosen URLs

content_visual_check({
  page_url: "https://<tenant>/<page-slug>",
  viewport: "desktop"
})
# → body_text_preview should still show your text content (overlay shouldn't hide it)
#   dom.media_elements should include {type: "video", src: "<the r2_url>"}
```

## Anti-patterns

- **Skipping the catalog browse** and hardcoding a `cdn.spideriq.ai/marketplace-bg-videos/...` URL. Catalog URLs may change; the browse is the contract.
- **Inserting via `content_update_page` with manually-constructed blocks[]** instead of `page_insert_section`. Loses the Phase 11+12 gate + the insertion-index preview.
- **`autoplay: true, muted: false`** — browsers block it. Always mute autoplay.
- **No `poster_url`** — blank section until buffer fills. Always pass it.
- **Looping `content_list_marketplace_bg_videos` with `limit: 200`** to "see everything." Filter by `category` + `tag` instead; the catalog is small but the bulk return is heavier than necessary.
- **Using the marketplace bg-video for short product demos** (15s+). Use a real `<video>` element with controls; bg-videos are for ambient loops.

## Verify the recipe → tool

```bash
./scripts/find-tool-for-intent.sh "add a looping background video to a page"
# Top-1 should be: recipes/marketplace/pick-bg-video.md
```

## See also

- [`browse-and-insert-section.md`](browse-and-insert-section.md) — the generic "browse marketplace + insert" pattern (this recipe is its bg-video specialisation)
- [`browse-cro-components.md`](browse-cro-components.md) — for capture / urgency / scarcity components (different catalog)
- [`author-bg-video.md`](author-bg-video.md) — publish a NEW clip to the catalog (super_admin only)
- [`../content/scroll-video-hero.md`](../content/scroll-video-hero.md) — when you want a scroll-scrubbed video (different primitive — `sys-scroll-sequence`, not `sys-bg-video`)
- [`../reference/deploy-protocol.md`](../reference/deploy-protocol.md) — `page_insert_section` is gated; the dry_run → confirm flow
