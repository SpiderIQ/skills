# recipes/content/duplicate-block

Insert a **deep copy of one block** into the same page — at any position. One call, not gated, fresh block UUID.

## When to use

- Duplicating a CTA section to use in a different position on the same page (top hero + mid-scroll + footer).
- Cloning a tier-priced "feature card" inside a `pricing-grid` block when the props were tuned just right.
- Building variations of the same section without rebuilding from scratch.
- Pattern: "do that thing again, just below the original."

## Prerequisites

- A PAT scoped to the tenant.
- The page's `page_id` (UUID).
- The source `block_id` to duplicate. Read it from `content_get_page` → `blocks[]`.

## The one call

```
content_duplicate_block({
  page_id:  "<page-uuid>",
  block_id: "<source-block-id>",
  position: "after"      # default; see below
})
# → { page: {...updated with new block inserted...}, new_block_id: "<fresh-uuid>" }
```

That's it. Not Phase 11+12 gated. Page status is unchanged — this won't unpublish a published page.

## `position` semantics

| Value | Behavior |
|---|---|
| `"after"` (default) | Insert immediately after the source block |
| `"before"` | Insert immediately before the source block |
| Integer (e.g. `0`, `3`, `99`) | Insert at the explicit 0-based index. Clamped to `[0, len(blocks)]` |

```
# Place the copy at the very top:
content_duplicate_block({ page_id, block_id: "blk_hero", position: 0 })

# Place the copy at the very end:
content_duplicate_block({ page_id, block_id: "blk_features", position: 999 })   # clamps to len
```

## What gets cloned

- The entire block JSON — `type`, `component_slug`, `component_version`, `props`, `data`, layout settings.
- The `block.id` is **regenerated** (fresh UUID); everything else is byte-identical.
- Intra-page `anchor_block_id` references INSIDE the duplicated block are NOT rewritten — if you duplicate a tabbed block whose internal panels reference each other by id, the copy's panels still reference the ORIGINAL panels. Audit after for tabbed/accordion/anchor patterns.

## Steps

```
1. content_get_page({ page_id })                   — find the block you want to duplicate
2. content_duplicate_block({ page_id, block_id })  — get the new block id
3. content_update_page({ page_id, blocks: [...] }) — (optional) edit the new block's copy/props
4. content_publish_page({ page_id })               — safe-default dry_run; review + confirm
5. content_deploy_site_preview() → content_deploy_site_production(confirm_token)
```

## Gotchas

- **The two copies share the same `component_slug` AND `component_version`.** If the underlying component gets a v4 published, both copies will pick it up on next deploy (the page references the slug, not a pinned version, unless you set `component_version` explicitly).
- **Forms inside duplicated blocks are NOT cloned.** If you duplicate a block whose `component_slug == "form"` and `data.flow_id` points at a flow, the copy points at the SAME flow. Submissions from both blocks land together. To isolate, duplicate the flow (`form_duplicate({ flow_id })`) and edit the copy's `data.flow_id`.
- **Tier 3 components (GSAP / scroll-sequence) cost CPU per instance.** Duplicating a `sys-scroll-sequence` block puts two GSAP timelines on the page; mobile users feel it. Audit performance after duplicating animation-heavy blocks.
- **Intra-block anchor refs don't rewrite.** Tab/accordion blocks with internal panel ids referencing each other will silently misbehave if the panels appear twice. Fix manually: edit the copy's internal ids in a follow-up `content_update_page`.
- **`position` greater than `len(blocks)` clamps to the end** — it doesn't error. Useful for "always append," but easy to confuse with off-by-one bugs.

## Verify

```
content_get_page({ page_id })
# → confirm blocks[] has the new block at the expected index
#   confirm new_block_id is in blocks[].id
#   confirm props match the source byte-identical (except .id)
```

For visual confirmation after deploy:

```
content_visual_check({
  page_url: "https://<tenant-domain>/<page-slug>",
  viewport: "desktop"
})
```

For form-containing duplicates, assert on `dom.shadow_hosts.includes("spideriq-form")` — see [`../reference/booking-model.md`](../reference/booking-model.md) and Rule 62.

## Anti-patterns

- **Calling `content_duplicate_block` 12× in a loop** to build a list. Use `content_update_page` with a constructed `blocks[]` instead — one round-trip vs 12.
- **Duplicating a block to "back it up" before editing.** Just edit; the version history (per-page) carries the snapshot already. Restore via [`restore-page-version.md`](restore-page-version.md) if needed.
- **Duplicating a form block expecting submission isolation.** The copy points at the same `flow_id` — submissions converge. Duplicate the flow if isolation matters.
- **Forgetting to edit the duplicate's copy/CTA text.** Two identical CTAs on the same page rarely lift conversion; you wanted "same component, different message."
- **Duplicating Tier 3 animation blocks without performance-budgeting.** Two scroll-sequences on mobile = jank. Use [`../audit/visual-check-a-page.md`](../audit/visual-check-a-page.md) post-deploy with `viewport: "mobile"` to catch this.

## See also

- [`duplicate-page.md`](duplicate-page.md) — same primitive at page granularity (full-page deep copy with fresh UUIDs everywhere)
- [`../components/find-component.md`](../components/find-component.md) — for inspecting what the duplicated component does
- [`section-override.md`](section-override.md) — when you want a "duplicate but with my version of one section" pattern
- [`../audit/visual-check-a-page.md`](../audit/visual-check-a-page.md) — verify the duplicate renders correctly
- [`../reference/block-types.md`](../reference/block-types.md) — the block schema being deep-copied
